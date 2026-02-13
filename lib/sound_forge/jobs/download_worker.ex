defmodule SoundForge.Jobs.DownloadWorker do
  @moduledoc """
  Oban worker for handling audio downloads from Spotify URLs.

  Replaces the Redis-based job queue from the TypeScript backend.
  Uses Phoenix.PubSub instead of Socket.IO for real-time progress updates.
  """
  use Oban.Worker,
    queue: :download,
    max_attempts: 3,
    priority: 1

  alias SoundForge.Audio.SpotDL
  alias SoundForge.Music

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "track_id" => track_id,
          "spotify_url" => spotify_url,
          "quality" => quality,
          "job_id" => job_id
        }
      }) do
    Logger.metadata(track_id: track_id, job_id: job_id, worker: "DownloadWorker")
    Logger.info("Starting download from #{spotify_url}")

    # Update job status to downloading
    job = Music.get_download_job!(job_id)
    Music.update_download_job(job, %{status: :downloading, progress: 0})
    broadcast_progress(job_id, :downloading, 0)
    broadcast_track_progress(track_id, :download, :downloading, 0)

    # Download via spotdl
    case SpotDL.download(spotify_url,
           output_dir: downloads_dir(),
           bitrate: quality,
           output_template: track_id
         ) do
      {:ok, %{path: output_path, size: file_size}} ->
        # Validate the downloaded file
        case validate_audio_file(output_path, file_size) do
          :ok ->
            Music.update_download_job(job, %{
              status: :completed,
              progress: 100,
              output_path: output_path,
              file_size: file_size
            })

            Logger.info("Download complete, file_size=#{file_size}")
            broadcast_progress(job_id, :completed, 100)
            broadcast_track_progress(track_id, :download, :completed, 100)

            # Chain: enqueue stem separation
            enqueue_processing(track_id, output_path)

            :ok

          {:error, reason} ->
            Logger.error("Download validation failed: #{reason}")
            Music.update_download_job(job, %{status: :failed, error: reason})
            broadcast_progress(job_id, :failed, 0)
            broadcast_track_progress(track_id, :download, :failed, 0)
            File.rm(output_path)
            {:error, reason}
        end

      {:error, reason} ->
        Music.update_download_job(job, %{status: :failed, error: reason})
        broadcast_progress(job_id, :failed, 0)
        broadcast_track_progress(track_id, :download, :failed, 0)
        {:error, reason}
    end
  end

  defp downloads_dir do
    Application.get_env(:sound_forge, :downloads_dir, "priv/uploads/downloads")
  end

  @default_min_audio_size 1024

  defp validate_audio_file(path, file_size) do
    min_size = Application.get_env(:sound_forge, :min_audio_size, @default_min_audio_size)

    cond do
      not File.exists?(path) ->
        {:error, "Downloaded file does not exist"}

      file_size < min_size ->
        {:error, "Downloaded file too small (#{file_size} bytes), likely corrupt"}

      true ->
        validate_audio_header(path)
    end
  end

  @valid_audio_headers [
    <<0xFF, 0xFB>>,
    <<0xFF, 0xFA>>,
    <<0xFF, 0xF3>>,
    <<0xFF, 0xF2>>,
    "ID3",
    "RIFF",
    "fLaC",
    "OggS"
  ]

  defp validate_audio_header(path) do
    case File.read(path) do
      {:ok, data} ->
        if Enum.any?(@valid_audio_headers, &String.starts_with?(data, &1)),
          do: :ok,
          else: {:error, "File does not appear to be a valid audio file"}

      {:error, reason} ->
        {:error, "Cannot read file: #{inspect(reason)}"}
    end
  end

  defp enqueue_processing(track_id, file_path) do
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
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to enqueue processing worker for track #{track_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to create processing job for track #{track_id}: #{inspect(reason)}")
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
