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

  alias SoundForge.Audio.DemucsPort
  alias SoundForge.Music

  require Logger

  @known_stem_types ~w(vocals drums bass other guitar piano)a

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "track_id" => track_id,
          "job_id" => job_id,
          "file_path" => file_path,
          "model" => model
        }
      }) do
    Logger.metadata(track_id: track_id, job_id: job_id, worker: "ProcessingWorker")
    Logger.info("Starting stem separation with model=#{model}")

    job = Music.get_processing_job!(job_id)
    Music.update_processing_job(job, %{status: :processing, progress: 0})
    broadcast_progress(job_id, :processing, 0)
    broadcast_track_progress(track_id, :processing, :processing, 0)

    progress_callback = fn percent, _message ->
      # Reload job to avoid stale struct race conditions
      fresh_job = Music.get_processing_job!(job_id)
      Music.update_processing_job(fresh_job, %{progress: percent})
      broadcast_progress(job_id, :processing, percent)
    end

    resolved_path = SoundForge.Storage.resolve_path(file_path)

    result =
      try do
        # Start a dedicated port process for this job
        {:ok, port_pid} = SoundForge.Audio.PortSupervisor.start_demucs()

        DemucsPort.separate(resolved_path,
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
        # The Python script returns absolute paths in stems map, so use them directly.
        # If a path is relative, resolve it against output_dir.
        stem_records =
          Enum.flat_map(stems, fn {stem_type, stem_path} ->
            resolved = if String.starts_with?(stem_path, "/"), do: stem_path, else: Path.join(output_dir, stem_path)
            create_stem_record(track_id, job_id, stem_type, resolved)
          end)

        # Reload to avoid stale struct
        fresh_job = Music.get_processing_job!(job_id)

        Music.update_processing_job(fresh_job, %{
          status: :completed,
          progress: 100,
          output_path: output_dir
        })

        Logger.info("Stem separation complete, stems=#{length(stem_records)}")
        broadcast_progress(job_id, :completed, 100)
        broadcast_track_progress(track_id, :processing, :completed, 100)

        # Chain: enqueue analysis job
        enqueue_analysis(track_id, file_path)

        {:ok, %{stems: length(stem_records)}}

      {:error, reason} ->
        error_msg = inspect(reason)
        Logger.error("Stem separation failed: #{error_msg}")
        # Reload to avoid stale struct
        fresh_job = Music.get_processing_job!(job_id)
        Music.update_processing_job(fresh_job, %{status: :failed, error: error_msg})
        broadcast_progress(job_id, :failed, 0)
        broadcast_track_progress(track_id, :processing, :failed, 0)

        # Clean up any partial output files
        cleanup_output(fresh_job)

        {:error, error_msg}
    end
  end

  defp create_stem_record(track_id, job_id, stem_type, stem_path) do
    stem_atom = safe_stem_type(stem_type)

    cond do
      is_nil(stem_atom) ->
        Logger.warning("Unknown stem type: #{stem_type}, skipping")
        []

      not File.exists?(stem_path) ->
        Logger.warning("Stem file missing: #{stem_path}")
        []

      true ->
        persist_stem(track_id, job_id, stem_type, stem_atom, stem_path)
    end
  end

  defp persist_stem(track_id, job_id, stem_type, stem_atom, stem_path) do
    file_size =
      case File.stat(stem_path) do
        {:ok, %{size: size}} -> size
        _ -> 0
      end

    case Music.create_stem(%{
           track_id: track_id,
           processing_job_id: job_id,
           stem_type: stem_atom,
           file_path: stem_path,
           file_size: file_size
         }) do
      {:ok, stem} ->
        [stem]

      {:error, reason} ->
        Logger.warning("Failed to create stem record for #{stem_type}: #{inspect(reason)}")
        []
    end
  end

  defp expected_stem_count("htdemucs_6s"), do: 6
  defp expected_stem_count(_model), do: 4

  defp safe_stem_type(type) when is_binary(type) do
    atom = String.to_existing_atom(type)
    if atom in @known_stem_types, do: atom, else: nil
  rescue
    ArgumentError -> nil
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
    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "jobs:#{job_id}",
      {:job_progress, %{job_id: job_id, status: status, progress: progress}}
    )
  end

  defp cleanup_output(job) do
    if job.output_path && File.dir?(job.output_path) do
      Logger.info("Cleaning up partial output at #{job.output_path}")
      File.rm_rf(job.output_path)
    end
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
