defmodule SoundForge.Jobs.MultiStemWorker do
  @moduledoc """
  Oban worker for multi-stem extraction using the lalal.ai multistem API.

  Uploads a track's audio file to lalal.ai, initiates a multistem split
  to extract up to 6 stems in a single request, polls for completion with
  exponential backoff, downloads each stem file, creates Stem records,
  broadcasts progress per-stem via PipelineBroadcaster, and chains
  AnalysisWorker for each created stem.

  ## Job Arguments

    - `"track_id"` - UUID of the Track record
    - `"job_id"` - UUID of the ProcessingJob record
    - `"file_path"` - Relative or absolute path to the audio file
    - `"stem_list"` - List of lalal.ai stem filter strings to extract
      (up to 6, e.g. `["vocals", "drum", "bass", "piano", "electricguitar", "acousticguitar"]`)
    - `"extraction_level"` - Extraction level passed to lalal.ai (default: "normal")
    - `"splitter"` - lalal.ai model name (default: "phoenix")

  ## Pipeline

  The worker progresses through these stages:
  1. `:queued` -> `:processing` (upload started)
  2. Upload file to lalal.ai, receive source_id
  3. Call `split_multistem/3` with the source_id and stem_list
  4. Poll for completion with exponential backoff (5s -> 60s cap, 120 max attempts)
  5. Download each extracted stem + back track
  6. Create Stem records, broadcasting progress per stem
  7. Chain `AnalysisWorker` for each created stem
  8. `:completed` on success
  """
  use Oban.Worker,
    queue: :processing,
    max_attempts: 3,
    priority: 2

  alias SoundForge.Audio.LalalAI
  alias SoundForge.Jobs.PipelineBroadcaster
  alias SoundForge.Music

  require Logger

  # Poll interval: start at 5 seconds, max 60 seconds
  @initial_poll_interval_ms 5_000
  @max_poll_interval_ms 60_000
  # Maximum total polling time: 20 minutes
  @max_poll_attempts 120

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "track_id" => track_id,
          "job_id" => job_id,
          "file_path" => file_path,
          "stem_list" => stem_list
        } = args
      }) do
    Logger.metadata(track_id: track_id, job_id: job_id, worker: "MultiStemWorker")

    extraction_level = Map.get(args, "extraction_level", "normal")
    splitter = Map.get(args, "splitter", "phoenix")

    Logger.info(
      "Starting multistem separation: stems=#{inspect(stem_list)}, " <>
        "extraction_level=#{extraction_level}, splitter=#{splitter}"
    )

    job = Music.get_processing_job!(job_id)
    Music.update_processing_job(job, %{status: :processing, progress: 0})
    broadcast_progress(job_id, :processing, 0)
    broadcast_track_progress(track_id, :processing, :processing, 0)

    resolved_path = SoundForge.Storage.resolve_path(file_path)

    unless File.exists?(resolved_path) do
      error_msg = "Audio file not found: #{resolved_path}"
      Logger.error(error_msg)
      fresh_job = Music.get_processing_job!(job_id)
      Music.update_processing_job(fresh_job, %{status: :failed, error: error_msg})
      PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :processing)
      raise error_msg
    end

    # Step 1: Upload the file to lalal.ai (v1.1 endpoint) to get a source_id
    with {:ok, source_id} <- LalalAI.upload_source(resolved_path),
         _ <- Logger.info("lalal.ai upload complete, source_id=#{source_id}"),
         _ <- broadcast_progress(job_id, :processing, 10),
         _ <-
           (fresh_upload_job = Music.get_processing_job!(job_id);
            Music.update_processing_job(fresh_upload_job, %{
              options: Map.put(fresh_upload_job.options || %{}, "lalalai_source_id", source_id)
            })),
         # Step 2: Initiate multistem split
         {:ok, split_result} <-
           LalalAI.split_multistem(source_id, stem_list,
             splitter: splitter,
             extraction_level: extraction_level
           ),
         _ <- Logger.info("lalal.ai multistem split initiated: #{inspect(split_result)}"),
         # Extract the task_id from split response for polling
         {:ok, task_id} <- extract_task_id(split_result),
         _ <- Logger.info("lalal.ai multistem task_id=#{task_id}"),
         _ <-
           (fresh_split_job = Music.get_processing_job!(job_id);
            Music.update_processing_job(fresh_split_job, %{
              options: Map.put(fresh_split_job.options || %{}, "lalalai_task_id", task_id)
            })),
         # Step 3: Poll until complete
         {:ok, stem_results} <- poll_until_complete(task_id, job_id, track_id) do
      # Step 4: Process all completed stems
      process_completed_stems(
        track_id,
        job_id,
        file_path,
        stem_results,
        stem_list,
        extraction_level,
        splitter
      )
    else
      {:error, reason} ->
        error_msg = inspect(reason)
        Logger.error("lalal.ai multistem separation failed: #{error_msg}")
        fresh_job = Music.get_processing_job!(job_id)
        Music.update_processing_job(fresh_job, %{status: :failed, error: error_msg})
        PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :processing)
        {:error, error_msg}
    end
  end

  # -- Private: Task ID extraction --

  # The split_multistem response may contain a task_id at the top level
  # or nested inside the response body. Handle both shapes.
  defp extract_task_id(%{"id" => task_id}) when is_binary(task_id), do: {:ok, task_id}
  defp extract_task_id(%{"task_id" => task_id}) when is_binary(task_id), do: {:ok, task_id}

  defp extract_task_id(%{"result" => result}) when is_map(result) do
    case Map.keys(result) do
      [task_id] when is_binary(task_id) -> {:ok, task_id}
      _ -> {:error, :no_task_id_in_result}
    end
  end

  defp extract_task_id(response) do
    Logger.error("Could not extract task_id from split_multistem response: #{inspect(response)}")
    {:error, {:no_task_id, response}}
  end

  # -- Private: Polling --

  defp poll_until_complete(task_id, job_id, track_id) do
    poll_until_complete(task_id, job_id, track_id, 0, @initial_poll_interval_ms)
  end

  defp poll_until_complete(_task_id, job_id, track_id, attempt, _interval)
       when attempt >= @max_poll_attempts do
    Logger.error("lalal.ai multistem polling timed out after #{attempt} attempts")
    fresh_job = Music.get_processing_job!(job_id)
    Music.update_processing_job(fresh_job, %{status: :failed, error: "Polling timeout"})
    PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :processing)
    {:error, :polling_timeout}
  end

  defp poll_until_complete(task_id, job_id, track_id, attempt, interval) do
    :timer.sleep(interval)

    case LalalAI.get_status(task_id) do
      {:ok, %{status: "success", stem: stem, back: back, accompaniment: accompaniment}} ->
        Logger.info("lalal.ai multistem task #{task_id} completed successfully")
        {:ok, %{task_id: task_id, stem: stem, back: back, accompaniment: accompaniment}}

      {:ok, %{status: "progress", queue_progress: queue_progress}} ->
        # Map queue_progress (0-100) to 15-90% of our progress bar
        # (10% reserved for upload, 90-100% for download/creation)
        progress = if queue_progress, do: trunc(15 + queue_progress * 0.75), else: 20 + attempt

        fresh_job = Music.get_processing_job!(job_id)
        Music.update_processing_job(fresh_job, %{progress: min(progress, 90)})
        broadcast_progress(job_id, :processing, min(progress, 90))

        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:ok, %{status: "queued"}} ->
        Logger.debug("lalal.ai multistem task #{task_id} still queued (attempt #{attempt})")
        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:ok, %{status: "error", error: error_message}} ->
        Logger.error("lalal.ai multistem task #{task_id} failed: #{error_message}")
        {:error, {:lalalai_error, error_message}}

      {:ok, %{status: unknown_status}} ->
        Logger.warning("lalal.ai multistem task #{task_id} unknown status: #{unknown_status}")
        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:error, reason} ->
        Logger.warning(
          "lalal.ai multistem status check failed (attempt #{attempt}): #{inspect(reason)}, retrying..."
        )

        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)
    end
  end

  # -- Private: Stem processing --

  defp process_completed_stems(
         track_id,
         job_id,
         file_path,
         stem_results,
         stem_list,
         extraction_level,
         splitter
       ) do
    stem_dir = build_stem_dir(track_id)
    File.mkdir_p!(stem_dir)

    # Download and persist each requested stem from the results
    stem_records =
      stem_list
      |> Enum.with_index()
      |> Enum.flat_map(fn {stem_filter, index} ->
        stem_type_atom = LalalAI.filter_to_stem_type(stem_filter) || :other

        download_url = extract_stem_download_url(stem_results, stem_filter, :stem)

        case download_url do
          url when is_binary(url) ->
            stem_filename = "#{stem_filter}.wav"
            stem_path = Path.join(stem_dir, stem_filename)

            case LalalAI.download_stem(url, stem_path) do
              {:ok, saved_path} ->
                relative_path = make_relative(saved_path)
                records = persist_stem(track_id, job_id, stem_type_atom, relative_path)

                # Broadcast progress per stem
                stem_progress = trunc(90 + (index + 1) / (length(stem_list) + 1) * 10)

                broadcast_progress(job_id, :processing, min(stem_progress, 99))

                broadcast_track_progress(
                  track_id,
                  :processing,
                  :processing,
                  min(stem_progress, 99)
                )

                Logger.info("Downloaded and saved stem: #{stem_filter} (#{stem_type_atom})")
                records

              {:error, reason} ->
                Logger.error("Failed to download stem #{stem_filter}: #{inspect(reason)}")
                []
            end

          nil ->
            Logger.warning("No download URL for stem #{stem_filter} in results")
            []
        end
      end)

    # Download the back track (accompaniment / everything-else mix) if present
    back_track_records = download_back_track(stem_results, stem_dir, track_id, job_id)

    all_stem_records = stem_records ++ back_track_records

    # Update the processing job as completed
    fresh_job = Music.get_processing_job!(job_id)

    job_options =
      Map.merge(fresh_job.options || %{}, %{
        "engine" => "lalalai",
        "mode" => "multistem",
        "stem_list" => stem_list,
        "extraction_level" => extraction_level,
        "splitter" => splitter
      })

    Music.update_processing_job(fresh_job, %{
      status: :completed,
      progress: 100,
      output_path: stem_dir,
      options: job_options
    })

    Logger.info("lalal.ai multistem separation complete, stems=#{length(all_stem_records)}")
    PipelineBroadcaster.broadcast_stage_complete(track_id, job_id, :processing)

    # Chain: enqueue analysis job for each created stem
    Enum.each(all_stem_records, fn stem ->
      enqueue_analysis(track_id, stem.file_path)
    end)

    # Also enqueue analysis for the original track
    enqueue_analysis(track_id, file_path)

    {:ok, %{stems: length(all_stem_records)}}
  end

  # Extract the download URL for a specific stem from the multistem results.
  # The API may return results keyed by stem filter name or nested in the
  # stem/accompaniment maps. We try multiple shapes.
  defp extract_stem_download_url(stem_results, stem_filter, _type) do
    # Shape 1: stem map has a "link" directly (single-stem compatible shape)
    case get_in_map(stem_results, [:stem, stem_filter, "link"]) do
      url when is_binary(url) -> url
      _ -> extract_stem_download_url_alt(stem_results, stem_filter)
    end
  end

  # Alternative extraction: the stem results may have the download link
  # directly inside the :stem map as %{"link" => url}
  defp extract_stem_download_url_alt(stem_results, stem_filter) do
    stem_data = Map.get(stem_results, :stem)

    cond do
      # Shape 2: stem is a map with filter-keyed sub-maps
      is_map(stem_data) && is_map(Map.get(stem_data, stem_filter)) ->
        Map.get(stem_data[stem_filter], "link")

      # Shape 3: stem is a map with string keys (from JSON decoding)
      is_map(stem_data) && is_binary(Map.get(stem_data, "link")) && stem_filter == "primary" ->
        Map.get(stem_data, "link")

      # Shape 4: single stem link (fallback for single-filter responses)
      is_map(stem_data) && is_binary(Map.get(stem_data, "link")) ->
        Map.get(stem_data, "link")

      true ->
        nil
    end
  end

  # Safe nested map access that handles both atom and string keys
  defp get_in_map(map, []) when is_map(map), do: map
  defp get_in_map(nil, _keys), do: nil

  defp get_in_map(map, [key | rest]) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, to_string(key))
    get_in_map(value, rest)
  end

  defp get_in_map(_map, _keys), do: nil

  # Download the accompaniment/back track if available.
  # The multistem API may return the back track as :back or :accompaniment.
  defp download_back_track(stem_results, stem_dir, track_id, job_id) do
    back = Map.get(stem_results, :back)
    accompaniment = Map.get(stem_results, :accompaniment)

    download_url =
      case back do
        %{"link" => url} when is_binary(url) ->
          url

        _ ->
          case accompaniment do
            %{"link" => url} when is_binary(url) -> url
            _ -> nil
          end
      end

    case download_url do
      url when is_binary(url) ->
        back_track_path = Path.join(stem_dir, "back_track.wav")

        case LalalAI.download_stem(url, back_track_path) do
          {:ok, saved_path} ->
            relative_path = make_relative(saved_path)
            records = persist_stem(track_id, job_id, :other, relative_path)
            Logger.info("Downloaded and saved back track")
            records

          {:error, reason} ->
            Logger.error("Failed to download back track: #{inspect(reason)}")
            []
        end

      nil ->
        []
    end
  end

  defp persist_stem(track_id, job_id, stem_type_atom, relative_path) do
    file_size =
      case File.stat(relative_path) do
        {:ok, %{size: size}} -> size
        _ -> 0
      end

    case Music.create_stem(%{
           track_id: track_id,
           processing_job_id: job_id,
           stem_type: stem_type_atom,
           file_path: relative_path,
           file_size: file_size,
           source: "lalalai"
         }) do
      {:ok, stem} ->
        [stem]

      {:error, reason} ->
        Logger.warning(
          "Failed to create stem record for #{stem_type_atom}: #{inspect(reason)}"
        )

        []
    end
  end

  defp build_stem_dir(track_id) do
    base = Application.get_env(:sound_forge, :storage_path, "priv/uploads")
    Path.join([base, "stems", track_id])
  end

  defp make_relative(absolute_path) do
    base = Application.get_env(:sound_forge, :storage_path, "priv/uploads")
    app_root = File.cwd!()
    abs_base = Path.expand(base, app_root)

    if String.starts_with?(absolute_path, abs_base) do
      Path.relative_to(absolute_path, app_root)
    else
      absolute_path
    end
  end

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
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to enqueue analysis worker for track #{track_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to create analysis job for track #{track_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp broadcast_progress(job_id, status, progress) do
    PipelineBroadcaster.broadcast_progress(job_id, status, progress)
  end

  defp broadcast_track_progress(track_id, stage, status, progress) do
    PipelineBroadcaster.broadcast_track_progress(track_id, stage, status, progress)
  end
end
