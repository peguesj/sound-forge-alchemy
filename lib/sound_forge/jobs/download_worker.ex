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

  alias SoundForge.Music

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "track_id" => track_id,
          "spotify_url" => spotify_url,
          "quality" => quality,
          "job_id" => job_id
        }
      }) do
    # Update job status to downloading
    job = Music.get_download_job!(job_id)
    Music.update_download_job(job, %{status: :downloading, progress: 0})
    broadcast_progress(job_id, :downloading, 0)

    # Execute download (yt-dlp/spotdl)
    case execute_download(spotify_url, quality, track_id) do
      {:ok, %{path: output_path, size: file_size}} ->
        Music.update_download_job(job, %{
          status: :completed,
          progress: 100,
          output_path: output_path,
          file_size: file_size
        })

        broadcast_progress(job_id, :completed, 100)
        :ok

      {:error, reason} ->
        Music.update_download_job(job, %{status: :failed, error: reason})
        broadcast_progress(job_id, :failed, 0)
        {:error, reason}
    end
  end

  defp execute_download(spotify_url, quality, track_id) do
    output_dir = Application.get_env(:sound_forge, :downloads_dir, "priv/uploads/downloads")
    File.mkdir_p!(output_dir)

    # Use track_id as filename to avoid conflicts
    output_file = Path.join(output_dir, "#{track_id}.mp3")

    args = [
      spotify_url,
      "--output",
      output_file,
      "--format",
      "mp3",
      "--bitrate",
      quality
    ]

    case System.cmd("spotdl", args, stderr_to_stdout: true) do
      {_output, 0} ->
        # Get file size
        file_size =
          case File.stat(output_file) do
            {:ok, %{size: size}} -> size
            {:error, _} -> 0
          end

        {:ok, %{path: output_file, size: file_size}}

      {error_output, _code} ->
        {:error, "Download failed: #{error_output}"}
    end
  end

  defp broadcast_progress(job_id, status, progress) do
    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "jobs:#{job_id}",
      {:job_progress, %{job_id: job_id, status: status, progress: progress}}
    )
  end
end
