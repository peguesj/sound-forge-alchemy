defmodule SoundForge.Jobs.ProcessingWorker do
  @moduledoc """
  Oban worker for stem separation using Demucs.

  Receives a processing job ID, calls DemucsPort to separate audio into stems,
  creates Stem records for each output, and enqueues an AnalysisWorker on completion.
  """
  use Oban.Worker,
    queue: :processing,
    max_attempts: 2,
    priority: 2

  alias SoundForge.Music
  alias SoundForge.Audio.DemucsPort

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "track_id" => track_id,
          "job_id" => job_id,
          "file_path" => file_path,
          "model" => model
        }
      }) do
    job = Music.get_processing_job!(job_id)
    Music.update_processing_job(job, %{status: :processing, progress: 0})
    broadcast_progress(job_id, :processing, 0)
    broadcast_track_progress(track_id, :processing, :processing, 0)

    progress_callback = fn percent, _message ->
      Music.update_processing_job(job, %{progress: percent})
      broadcast_progress(job_id, :processing, percent)
    end

    # Start a dedicated port process for this job
    {:ok, port_pid} = SoundForge.Audio.PortSupervisor.start_demucs()

    result =
      try do
        DemucsPort.separate(file_path,
          model: model,
          progress_callback: progress_callback,
          server: port_pid
        )
      catch
        :exit, reason ->
          {:error, "Port process crashed: #{inspect(reason)}"}
      end

    case result do
      {:ok, %{stems: stems, output_dir: output_dir}} ->
        # Validate stem count (htdemucs produces 4, htdemucs_6s produces 6)
        expected = expected_stem_count(model)

        if map_size(stems) < expected do
          Logger.warning(
            "Expected #{expected} stems from #{model}, got #{map_size(stems)} for track #{track_id}"
          )
        end

        # Create Stem records for each separated stem
        stem_records =
          Enum.flat_map(stems, fn {stem_type, relative_path} ->
            stem_path = Path.join(output_dir, relative_path)

            if File.exists?(stem_path) do
              file_size =
                case File.stat(stem_path) do
                  {:ok, %{size: size}} -> size
                  _ -> 0
                end

              {:ok, stem} =
                Music.create_stem(%{
                  track_id: track_id,
                  processing_job_id: job_id,
                  stem_type: String.to_existing_atom(stem_type),
                  file_path: stem_path,
                  file_size: file_size
                })

              [stem]
            else
              Logger.warning("Stem file missing: #{stem_path}")
              []
            end
          end)

        Music.update_processing_job(job, %{
          status: :completed,
          progress: 100,
          output_path: output_dir
        })

        broadcast_progress(job_id, :completed, 100)
        broadcast_track_progress(track_id, :processing, :completed, 100)

        # Chain: enqueue analysis job
        enqueue_analysis(track_id, file_path)

        {:ok, %{stems: length(stem_records)}}

      {:error, reason} ->
        error_msg = inspect(reason)
        Music.update_processing_job(job, %{status: :failed, error: error_msg})
        broadcast_progress(job_id, :failed, 0)
        broadcast_track_progress(track_id, :processing, :failed, 0)
        {:error, error_msg}
    end
  end

  defp expected_stem_count("htdemucs_6s"), do: 6
  defp expected_stem_count(_model), do: 4

  defp enqueue_analysis(track_id, file_path) do
    case Music.create_analysis_job(%{track_id: track_id, status: :queued}) do
      {:ok, analysis_job} ->
        %{
          "track_id" => track_id,
          "job_id" => analysis_job.id,
          "file_path" => file_path,
          "features" => ["tempo", "key", "energy", "spectral"]
        }
        |> SoundForge.Jobs.AnalysisWorker.new()
        |> Oban.insert()

      {:error, reason} ->
        Logger.error("Failed to create analysis job for track #{track_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp broadcast_progress(job_id, status, progress) do
    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "jobs:#{job_id}",
      {:job_progress, %{job_id: job_id, status: status, progress: progress}}
    )
  end

  defp broadcast_track_progress(track_id, stage, status, progress) do
    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "track_pipeline:#{track_id}",
      {:pipeline_progress,
       %{track_id: track_id, stage: stage, status: status, progress: progress}}
    )
  end
end
