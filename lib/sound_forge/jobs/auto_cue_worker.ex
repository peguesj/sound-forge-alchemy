defmodule SoundForge.Jobs.AutoCueWorker do
  @moduledoc """
  Oban worker for automatic cue point generation using arrangement analysis.

  Accepts a track_id and user_id, checks for an existing analysis result
  (chaining AnalysisWorker if missing), calls the Python analyzer with the
  `auto_cues` feature, and persists the resulting cue points with
  `auto_generated: true`.

  Broadcasts `:auto_cues_complete` on PubSub topic `"tracks:{track_id}"`.
  """
  use Oban.Worker,
    queue: :analysis,
    max_attempts: 3,
    priority: 3

  alias SoundForge.Audio.AnalyzerPort
  alias SoundForge.DJ
  alias SoundForge.Music
  alias SoundForge.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"track_id" => track_id, "user_id" => user_id}
      }) do
    Logger.metadata(track_id: track_id, user_id: user_id, worker: "AutoCueWorker")
    Logger.info("Starting auto-cue generation")

    with {:ok, file_path} <- resolve_audio_path(track_id),
         :ok <- ensure_analysis_exists(track_id, file_path),
         {:ok, auto_cues} <- extract_auto_cues(file_path),
         {:ok, cue_points} <- persist_cue_points(auto_cues, track_id, user_id) do
      broadcast_completion(track_id, cue_points)
      Logger.info("Auto-cue generation complete, created #{length(cue_points)} cue points")
      :ok
    else
      {:snooze, seconds} ->
        Logger.info("Snoozing for #{seconds}s while analysis completes")
        {:snooze, seconds}

      {:error, reason} ->
        Logger.error("Auto-cue generation failed: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  @spec resolve_audio_path(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp resolve_audio_path(track_id) do
    case Music.get_download_path(track_id) do
      {:ok, path} ->
        resolved = SoundForge.Storage.resolve_path(path)

        if File.exists?(resolved) do
          {:ok, resolved}
        else
          {:error, "Audio file not found: #{resolved}"}
        end

      {:error, :no_completed_download} ->
        {:error, :no_completed_download}
    end
  end

  @spec ensure_analysis_exists(String.t(), String.t()) :: :ok | {:snooze, pos_integer()} | {:error, term()}
  defp ensure_analysis_exists(track_id, file_path) do
    case Music.get_analysis_result_for_track(track_id) do
      %{} ->
        Logger.debug("Analysis result already exists for track #{track_id}")
        :ok

      nil ->
        Logger.info("No analysis result found, chaining AnalysisWorker for track #{track_id}")
        chain_analysis_worker(track_id, file_path)
    end
  end

  @spec chain_analysis_worker(String.t(), String.t()) :: {:snooze, pos_integer()} | {:error, term()}
  defp chain_analysis_worker(track_id, file_path) do
    case Music.create_analysis_job(%{track_id: track_id, status: :queued}) do
      {:ok, analysis_job} ->
        %{
          "track_id" => track_id,
          "job_id" => analysis_job.id,
          "file_path" => file_path,
          "features" => ["tempo", "key", "energy", "structure"]
        }
        |> SoundForge.Jobs.AnalysisWorker.new()
        |> Oban.insert()
        |> case do
          {:ok, _} ->
            Logger.info("Chained AnalysisWorker for track #{track_id}")
            # Snooze this job to retry after analysis completes
            {:snooze, 30}

          {:error, reason} ->
            {:error, {:chain_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:create_analysis_job_failed, reason}}
    end
  end

  @spec extract_auto_cues(String.t()) :: {:ok, list(map())} | {:error, term()}
  defp extract_auto_cues(file_path) do
    Logger.info("Extracting auto cues from #{file_path}")

    result =
      try do
        {:ok, port_pid} = SoundForge.Audio.PortSupervisor.start_analyzer()
        AnalyzerPort.analyze(file_path, ["auto_cues"], server: port_pid)
      catch
        :exit, reason ->
          {:error, "Port process crashed: #{inspect(reason)}"}
      end

    case result do
      {:ok, %{"auto_cues" => cues}} when is_list(cues) ->
        Logger.info("Extracted #{length(cues)} auto cue candidates")
        {:ok, cues}

      {:ok, _results} ->
        Logger.warning("Python analyzer returned no auto_cues key")
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec persist_cue_points(list(map()), String.t(), integer() | String.t()) ::
          {:ok, list(DJ.CuePoint.t())} | {:error, term()}
  defp persist_cue_points(auto_cues, track_id, user_id) do
    # Remove existing auto-generated cues for this track+user before inserting
    delete_existing_auto_cues(track_id, user_id)

    results =
      Enum.map(auto_cues, fn cue ->
        attrs = %{
          track_id: track_id,
          user_id: user_id,
          position_ms: cue["position_ms"],
          label: cue["label"],
          color: cue["color"],
          cue_type: map_cue_type(cue["cue_type"]),
          auto_generated: true,
          confidence: cue["confidence"]
        }

        DJ.create_cue_point(attrs)
      end)

    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    if length(failures) > 0 do
      Logger.warning("#{length(failures)} cue points failed to persist")
    end

    cue_points = Enum.map(successes, fn {:ok, cp} -> cp end)
    {:ok, cue_points}
  end

  defp delete_existing_auto_cues(track_id, user_id) do
    import Ecto.Query

    {count, _} =
      DJ.CuePoint
      |> where([cp], cp.track_id == ^track_id and cp.user_id == ^user_id and cp.auto_generated == true)
      |> Repo.delete_all()

    if count > 0 do
      Logger.info("Deleted #{count} existing auto-generated cue points")
    end
  end

  # Map Python marker types to CuePoint cue_type enum values.
  # The CuePoint schema supports :hot, :loop_in, :loop_out, :memory.
  # Auto-generated cues are stored as :memory type (persistent navigation markers).
  @spec map_cue_type(String.t() | nil) :: :hot | :loop_in | :loop_out | :memory
  defp map_cue_type("drop"), do: :hot
  defp map_cue_type("build_up"), do: :hot
  defp map_cue_type(_), do: :memory

  defp broadcast_completion(track_id, cue_points) do
    SoundForgeWeb.Endpoint.broadcast(
      "tracks:#{track_id}",
      "auto_cues_complete",
      %{
        track_id: track_id,
        cue_point_count: length(cue_points),
        cue_points: Enum.map(cue_points, &serialize_cue_point/1)
      }
    )
  end

  defp serialize_cue_point(%DJ.CuePoint{} = cp) do
    %{
      id: cp.id,
      position_ms: cp.position_ms,
      label: cp.label,
      color: cp.color,
      cue_type: cp.cue_type,
      confidence: cp.confidence,
      auto_generated: cp.auto_generated
    }
  end
end
