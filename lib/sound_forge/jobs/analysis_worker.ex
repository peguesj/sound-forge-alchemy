defmodule SoundForge.Jobs.AnalysisWorker do
  @moduledoc """
  Oban worker for audio analysis using librosa via AnalyzerPort.

  Receives an analysis job ID, calls AnalyzerPort to extract audio features,
  and creates an AnalysisResult record with the extracted data.
  """
  use Oban.Worker,
    queue: :analysis,
    max_attempts: 2,
    priority: 2

  alias SoundForge.Audio.AnalyzerPort
  alias SoundForge.Jobs.PipelineBroadcaster
  alias SoundForge.Music

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "track_id" => track_id,
          "job_id" => job_id,
          "file_path" => file_path,
          "features" => features
        }
      }) do
    Logger.metadata(track_id: track_id, job_id: job_id, worker: "AnalysisWorker")
    Logger.info("Starting analysis, features=#{inspect(features)}")

    job = Music.get_analysis_job!(job_id)
    Music.update_analysis_job(job, %{status: :processing, progress: 0})
    PipelineBroadcaster.broadcast_stage_started(track_id, job_id, :analysis)
    broadcast_progress(job_id, :processing, 0)
    broadcast_track_progress(track_id, :analysis, :processing, 0)

    # Resolve relative paths to absolute (relative to app root)
    resolved_path = SoundForge.Storage.resolve_path(file_path)

    # Validate input file exists
    if File.exists?(resolved_path) do
      do_analysis(job, track_id, job_id, resolved_path, features)
    else
      error_msg = "Audio file not found: #{resolved_path}"
      Logger.error(error_msg)
      Music.update_analysis_job(job, %{status: :failed, error: error_msg})
      PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :analysis)
      {:error, error_msg}
    end
  end

  defp do_analysis(job, track_id, job_id, file_path, features) do
    result =
      try do
        # Start a dedicated port process for this job
        {:ok, port_pid} = SoundForge.Audio.PortSupervisor.start_analyzer()
        AnalyzerPort.analyze(file_path, features, server: port_pid)
      catch
        :exit, reason ->
          {:error, "Port process crashed: #{inspect(reason)}"}
      end

    case result do
      {:ok, results} ->
        # Remove existing analysis to prevent duplicates on re-analysis
        Music.delete_analysis_for_track(track_id)

        # Create AnalysisResult record
        # The Python analyzer returns a flat JSON structure, not nested
        {:ok, _analysis_result} =
          Music.create_analysis_result(%{
            track_id: track_id,
            analysis_job_id: job_id,
            tempo: results["tempo"],
            key: results["key"],
            energy: results["energy"],
            spectral_centroid: results["spectral_centroid"],
            spectral_rolloff: results["spectral_rolloff"],
            zero_crossing_rate: results["zero_crossing_rate"],
            features: results
          })

        Music.update_analysis_job(job, %{
          status: :completed,
          progress: 100,
          results: results
        })

        Logger.info("Analysis complete")
        PipelineBroadcaster.broadcast_stage_complete(track_id, job_id, :analysis)

        # Broadcast that the track is fully processed
        PipelineBroadcaster.broadcast_pipeline_complete(track_id)

        :ok

      {:error, reason} ->
        error_msg = inspect(reason)
        Logger.error("Analysis failed: #{error_msg}")
        Music.update_analysis_job(job, %{status: :failed, error: error_msg})
        PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :analysis)
        {:error, error_msg}
    end
  end

  defp broadcast_progress(job_id, status, progress) do
    PipelineBroadcaster.broadcast_progress(job_id, status, progress)
  end

  defp broadcast_track_progress(track_id, stage, status, progress) do
    PipelineBroadcaster.broadcast_track_progress(track_id, stage, status, progress)
  end
end
