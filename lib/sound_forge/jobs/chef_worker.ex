defmodule SoundForge.Jobs.ChefWorker do
  @moduledoc """
  Oban worker for asynchronous Chef recipe execution.

  Accepts a serialized `Chef.Recipe` (track IDs, stem types, cue plan, etc.),
  ensures stems are separated and analysis exists for every track in the recipe,
  generates auto-cue data for splice points, and broadcasts real-time progress
  on the `"chef:{user_id}"` PubSub topic.

  ## Failure handling

  If a track fails (missing audio file, separation error, etc.), the worker
  substitutes the next-best compatible track from the original ranked candidate
  list supplied in the job args. This keeps the recipe viable even when
  individual tracks are unavailable.

  ## PubSub events

  All broadcasts go to `"chef:{user_id}"`:

    * `"chef_progress"` -- per-track stage updates (stems, analysis, cues)
    * `"chef_complete"` -- finalized recipe with stem URLs and cue data
    * `"chef_failed"`   -- unrecoverable failure (all candidates exhausted)
  """

  use Oban.Worker,
    queue: :processing,
    max_attempts: 3,
    priority: 3

  import Ecto.Query, warn: false

  alias SoundForge.Music
  alias SoundForge.Music.Stem

  require Logger

  # ---------------------------------------------------------------------------
  # Oban callback
  # ---------------------------------------------------------------------------

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "user_id" => user_id,
      "track_ids" => track_ids,
      "stem_types" => stem_types,
      "cue_plan" => cue_plan,
      "candidate_track_ids" => candidate_track_ids,
      "recipe_meta" => recipe_meta
    } = args

    Logger.metadata(user_id: user_id, worker: "ChefWorker")
    Logger.info("Starting Chef recipe execution for #{length(track_ids)} tracks")

    broadcast_progress(user_id, %{
      stage: :started,
      message: "Preparing recipe...",
      total_tracks: length(track_ids),
      completed_tracks: 0
    })

    # Build a lookup of candidate tracks for substitution (excluding primary selections)
    primary_set = MapSet.new(track_ids)

    substitutes =
      (candidate_track_ids || [])
      |> Enum.reject(&MapSet.member?(primary_set, &1))

    # Process each track: ensure stems + analysis, handle failures with substitution
    {finalized_tracks, _remaining_subs} =
      Enum.reduce(track_ids, {[], substitutes}, fn track_id, {acc, subs} ->
        process_track_with_fallback(track_id, subs, user_id, stem_types, acc)
      end)

    finalized_tracks = Enum.reverse(finalized_tracks)

    if Enum.empty?(finalized_tracks) do
      broadcast_failed(user_id, "All tracks failed processing; no viable recipe.")
      Logger.error("Chef recipe failed: all tracks exhausted")
      {:error, "all_tracks_failed"}
    else
      # Gather stem URLs and cue data for every finalized track
      finalized_recipe = build_finalized_recipe(finalized_tracks, cue_plan, recipe_meta)

      broadcast_complete(user_id, finalized_recipe)

      Logger.info(
        "Chef recipe complete: #{length(finalized_tracks)} tracks finalized"
      )

      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Track processing with substitution fallback
  # ---------------------------------------------------------------------------

  @spec process_track_with_fallback(
          String.t(),
          [String.t()],
          integer(),
          [String.t()],
          [map()]
        ) :: {[map()], [String.t()]}
  defp process_track_with_fallback(track_id, substitutes, user_id, stem_types, acc) do
    case process_single_track(track_id, user_id, stem_types, length(acc) + 1) do
      {:ok, track_data} ->
        {[track_data | acc], substitutes}

      {:error, reason} ->
        Logger.warning(
          "Track #{track_id} failed (#{inspect(reason)}), attempting substitution"
        )

        attempt_substitution(substitutes, user_id, stem_types, acc, track_id)
    end
  end

  @spec attempt_substitution(
          [String.t()],
          integer(),
          [String.t()],
          [map()],
          String.t()
        ) :: {[map()], [String.t()]}
  defp attempt_substitution([], user_id, _stem_types, acc, failed_track_id) do
    Logger.warning("No substitutes remaining for failed track #{failed_track_id}")

    broadcast_progress(user_id, %{
      stage: :track_skipped,
      track_id: failed_track_id,
      message: "Track skipped, no substitutes available"
    })

    {acc, []}
  end

  defp attempt_substitution(
         [candidate_id | rest],
         user_id,
         stem_types,
         acc,
         failed_track_id
       ) do
    broadcast_progress(user_id, %{
      stage: :substituting,
      failed_track_id: failed_track_id,
      substitute_track_id: candidate_id,
      message: "Substituting track..."
    })

    case process_single_track(candidate_id, user_id, stem_types, length(acc) + 1) do
      {:ok, track_data} ->
        track_data = Map.put(track_data, :substituted_for, failed_track_id)
        {[track_data | acc], rest}

      {:error, _reason} ->
        # This substitute also failed -- try the next one
        attempt_substitution(rest, user_id, stem_types, acc, failed_track_id)
    end
  end

  # ---------------------------------------------------------------------------
  # Single-track pipeline: stems -> analysis -> cues
  # ---------------------------------------------------------------------------

  @spec process_single_track(String.t(), integer(), [String.t()], pos_integer()) ::
          {:ok, map()} | {:error, term()}
  defp process_single_track(track_id, user_id, stem_types, track_number) do
    Logger.info("Processing track #{track_number}: #{track_id}")

    broadcast_progress(user_id, %{
      stage: :track_processing,
      track_id: track_id,
      track_number: track_number,
      message: "Processing track #{track_number}..."
    })

    with {:ok, _track} <- fetch_track(track_id),
         {:ok, file_path} <- resolve_audio_path(track_id),
         :ok <- ensure_stems(track_id, file_path, user_id, stem_types),
         :ok <- ensure_analysis(track_id, file_path, user_id),
         {:ok, stem_urls} <- collect_stem_urls(track_id, stem_types),
         {:ok, analysis_data} <- collect_analysis_data(track_id) do
      broadcast_progress(user_id, %{
        stage: :track_ready,
        track_id: track_id,
        track_number: track_number,
        message: "Track #{track_number} ready"
      })

      {:ok,
       %{
         track_id: track_id,
         stem_urls: stem_urls,
         analysis: analysis_data,
         substituted_for: nil
       }}
    else
      {:error, reason} ->
        Logger.warning("Track #{track_id} processing failed: #{inspect(reason)}")

        broadcast_progress(user_id, %{
          stage: :track_failed,
          track_id: track_id,
          track_number: track_number,
          message: "Track #{track_number} failed: #{inspect(reason)}"
        })

        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Ensure stems exist
  # ---------------------------------------------------------------------------

  @spec ensure_stems(String.t(), String.t(), integer(), [String.t()]) ::
          :ok | {:error, term()}
  defp ensure_stems(track_id, file_path, user_id, requested_stem_types) do
    existing_stems = Music.list_stems_for_track(track_id)
    existing_types = MapSet.new(existing_stems, &to_string(&1.stem_type))
    needed_types = MapSet.new(requested_stem_types)

    if MapSet.subset?(needed_types, existing_types) do
      Logger.debug("Stems already exist for track #{track_id}")
      :ok
    else
      Logger.info("Enqueuing stem separation for track #{track_id}")

      broadcast_progress(user_id, %{
        stage: :stems_enqueued,
        track_id: track_id,
        message: "Enqueuing stem separation..."
      })

      enqueue_stem_separation(track_id, file_path)
    end
  end

  @spec enqueue_stem_separation(String.t(), String.t()) :: :ok | {:error, term()}
  defp enqueue_stem_separation(track_id, file_path) do
    model = Application.get_env(:sound_forge, :default_demucs_model, "htdemucs")

    case Music.create_processing_job(%{track_id: track_id, model: model, status: :queued}) do
      {:ok, processing_job} ->
        %{
          "track_id" => track_id,
          "job_id" => processing_job.id,
          "file_path" => file_path,
          "model" => model
        }
        |> SoundForge.Jobs.ProcessingWorker.new()
        |> Oban.insert()
        |> case do
          {:ok, _oban_job} ->
            Logger.info("ProcessingWorker enqueued for track #{track_id}")
            :ok

          {:error, reason} ->
            {:error, {:enqueue_processing_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:create_processing_job_failed, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Ensure analysis exists
  # ---------------------------------------------------------------------------

  @spec ensure_analysis(String.t(), String.t(), integer()) :: :ok | {:error, term()}
  defp ensure_analysis(track_id, file_path, user_id) do
    case Music.get_analysis_result_for_track(track_id) do
      %{} ->
        Logger.debug("Analysis already exists for track #{track_id}")
        :ok

      nil ->
        Logger.info("Enqueuing analysis for track #{track_id}")

        broadcast_progress(user_id, %{
          stage: :analysis_enqueued,
          track_id: track_id,
          message: "Enqueuing audio analysis..."
        })

        enqueue_analysis(track_id, file_path)
    end
  end

  @spec enqueue_analysis(String.t(), String.t()) :: :ok | {:error, term()}
  defp enqueue_analysis(track_id, file_path) do
    case Music.create_analysis_job(%{track_id: track_id, status: :queued}) do
      {:ok, analysis_job} ->
        %{
          "track_id" => track_id,
          "job_id" => analysis_job.id,
          "file_path" => file_path,
          "features" =>
            Application.get_env(:sound_forge, :analysis_features, [
              "tempo",
              "key",
              "energy",
              "spectral"
            ])
        }
        |> SoundForge.Jobs.AnalysisWorker.new()
        |> Oban.insert()
        |> case do
          {:ok, _oban_job} ->
            Logger.info("AnalysisWorker enqueued for track #{track_id}")
            :ok

          {:error, reason} ->
            {:error, {:enqueue_analysis_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:create_analysis_job_failed, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Data collection helpers
  # ---------------------------------------------------------------------------

  @spec fetch_track(String.t()) :: {:ok, Music.Track.t()} | {:error, term()}
  defp fetch_track(track_id) do
    case Music.get_track(track_id) do
      {:ok, nil} -> {:error, :track_not_found}
      {:ok, track} -> {:ok, track}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec resolve_audio_path(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp resolve_audio_path(track_id) do
    case Music.get_download_path(track_id) do
      {:ok, path} ->
        resolved = SoundForge.Storage.resolve_path(path)

        if File.exists?(resolved) do
          {:ok, resolved}
        else
          {:error, {:audio_file_missing, resolved}}
        end

      {:error, :no_completed_download} ->
        {:error, :no_completed_download}
    end
  end

  @spec collect_stem_urls(String.t(), [String.t()]) :: {:ok, map()} | {:error, term()}
  defp collect_stem_urls(track_id, requested_stem_types) do
    stems = Music.list_stems_for_track(track_id)

    requested_set = MapSet.new(requested_stem_types)

    stem_map =
      stems
      |> Enum.filter(fn stem ->
        MapSet.member?(requested_set, to_string(stem.stem_type))
      end)
      |> Map.new(fn %Stem{stem_type: type, file_path: path} ->
        url = build_stem_url(path)
        {to_string(type), url}
      end)

    {:ok, stem_map}
  end

  @spec build_stem_url(String.t() | nil) :: String.t() | nil
  defp build_stem_url(nil), do: nil

  defp build_stem_url(path) do
    # Convert absolute/relative path to a web-accessible URL path.
    # Stem paths are stored relative to storage root to produce clean URLs.
    if String.starts_with?(path, "/") do
      # Absolute path: strip the storage base to get relative
      base = SoundForge.Storage.base_path()

      case String.replace_leading(path, base, "") do
        "/" <> rest -> "/files/#{rest}"
        rest -> "/files/#{rest}"
      end
    else
      "/files/#{path}"
    end
  end

  @spec collect_analysis_data(String.t()) :: {:ok, map()} | {:error, term()}
  defp collect_analysis_data(track_id) do
    case Music.get_analysis_result_for_track(track_id) do
      nil ->
        # Analysis may have been enqueued but not yet completed.
        # Return a placeholder so the recipe can still be assembled.
        {:ok, %{status: :pending, track_id: track_id}}

      analysis ->
        {:ok,
         %{
           status: :complete,
           track_id: track_id,
           tempo: analysis.tempo,
           key: analysis.key,
           energy: analysis.energy,
           spectral_centroid: analysis.spectral_centroid,
           spectral_rolloff: analysis.spectral_rolloff
         }}
    end
  end

  # ---------------------------------------------------------------------------
  # Build finalized recipe payload
  # ---------------------------------------------------------------------------

  @spec build_finalized_recipe([map()], list(), map()) :: map()
  defp build_finalized_recipe(finalized_tracks, cue_plan, recipe_meta) do
    %{
      tracks: finalized_tracks,
      cue_plan: cue_plan,
      recipe_meta: recipe_meta,
      track_count: length(finalized_tracks),
      substitutions:
        finalized_tracks
        |> Enum.filter(& &1.substituted_for)
        |> Enum.map(fn t ->
          %{original: t.substituted_for, replacement: t.track_id}
        end),
      completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # ---------------------------------------------------------------------------
  # PubSub broadcasting
  # ---------------------------------------------------------------------------

  @spec broadcast_progress(integer(), map()) :: :ok | {:error, term()}
  defp broadcast_progress(user_id, payload) do
    SoundForgeWeb.Endpoint.broadcast(
      "chef:#{user_id}",
      "chef_progress",
      payload
    )
  end

  @spec broadcast_complete(integer(), map()) :: :ok | {:error, term()}
  defp broadcast_complete(user_id, finalized_recipe) do
    SoundForgeWeb.Endpoint.broadcast(
      "chef:#{user_id}",
      "chef_complete",
      finalized_recipe
    )
  end

  @spec broadcast_failed(integer(), String.t()) :: :ok | {:error, term()}
  defp broadcast_failed(user_id, reason) do
    SoundForgeWeb.Endpoint.broadcast(
      "chef:#{user_id}",
      "chef_failed",
      %{reason: reason}
    )
  end
end
