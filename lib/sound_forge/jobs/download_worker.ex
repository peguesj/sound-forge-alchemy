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
  alias SoundForge.Jobs.PipelineBroadcaster
  alias SoundForge.Music

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "track_id" => track_id,
          "spotify_url" => spotify_url,
          "quality" => quality,
          "job_id" => job_id
        },
        attempt: attempt
      } = oban_job) do
    Logger.metadata(track_id: track_id, job_id: job_id, worker: "DownloadWorker", stage: "download")

    Logger.info(
      "[oban.DownloadWorker] perform entry: track_id=#{track_id} spotify_url=#{spotify_url} quality=#{quality} attempt=#{attempt}/#{oban_job.max_attempts}"
    )

    # Update job status to downloading
    job = Music.get_download_job!(job_id)
    Music.update_download_job(job, %{status: :downloading, progress: 0})
    broadcast_progress(job_id, :downloading, 0)
    broadcast_track_progress(track_id, :download, :downloading, 0)

    # Download via spotdl (Spotify API -> YouTube -> yt-dlp)
    dl_opts = [output_dir: downloads_dir(), bitrate: quality, output_template: track_id]

    case SpotDL.download(spotify_url, dl_opts) do
      {:ok, result} ->
        Logger.debug("[oban.DownloadWorker] SpotDL.download returned :ok, path=#{result.path} size=#{result.size}")
        handle_download_success(result, track_id, job_id, job)

      {:error, reason} ->
        Logger.debug("[oban.DownloadWorker] SpotDL.download returned :error, reason=#{reason}")
        Logger.warning("[oban.DownloadWorker] Spotify download failed: #{reason} -- attempting direct fallback")
        attempt_direct_fallback(track_id, job_id, job, dl_opts, reason)
    end
  end

  defp handle_download_success(%{path: output_path, size: file_size}, track_id, job_id, job) do
    Logger.metadata(stage: "validate")
    Logger.debug("[oban.DownloadWorker] validating output_path=#{output_path} file_size=#{file_size}")

    case validate_audio_file(output_path, file_size) do
      :ok ->
        Logger.debug("[oban.DownloadWorker] validation passed for output_path=#{output_path}")

        Music.update_download_job(job, %{
          status: :completed,
          progress: 100,
          output_path: output_path,
          file_size: file_size
        })

        Logger.info("[oban.DownloadWorker] download complete: output_path=#{output_path} file_size=#{file_size}")
        PipelineBroadcaster.broadcast_stage_complete(track_id, job_id, :download)

        enqueue_processing(track_id, output_path)

        :ok

      {:error, reason} ->
        Logger.debug("[oban.DownloadWorker] validation failed: #{reason}")
        Logger.error("[oban.DownloadWorker] download validation failed: #{reason}")
        Music.update_download_job(job, %{status: :failed, error: reason})
        PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :download)
        File.rm(output_path)
        {:error, reason}
    end
  end

  defp attempt_direct_fallback(track_id, job_id, job, dl_opts, original_reason) do
    Logger.metadata(stage: "fallback")
    track = Music.get_track!(track_id)

    if has_searchable_metadata?(track) do
      Logger.info(
        "[oban.DownloadWorker] fallback: title=#{track.title} artist=#{track.artist} duration=#{inspect(track.duration)}"
      )

      metadata = %{title: track.title, artist: track.artist, duration: track.duration}

      case SpotDL.download_direct(metadata, dl_opts) do
        {:ok, result} ->
          Logger.info("[oban.DownloadWorker] direct fallback succeeded for track #{track_id}")
          handle_download_success(result, track_id, job_id, job)

        {:error, fallback_reason} ->
          Logger.error("[oban.DownloadWorker] direct fallback also failed: #{fallback_reason}")
          Music.update_download_job(job, %{status: :failed, error: original_reason})
          PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :download)
          {:error, original_reason}
      end
    else
      Logger.error("[oban.DownloadWorker] cannot attempt direct fallback: track #{track_id} missing title/artist")
      Music.update_download_job(job, %{status: :failed, error: original_reason})
      PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :download)
      {:error, original_reason}
    end
  end

  defp has_searchable_metadata?(track) do
    is_binary(track.title) and track.title != "" and
      is_binary(track.artist) and track.artist != ""
  end

  defp downloads_dir do
    configured = Application.get_env(:sound_forge, :downloads_dir, "priv/uploads/downloads")

    if String.starts_with?(configured, "/") do
      configured
    else
      Path.join(Application.app_dir(:sound_forge), configured) |> Path.expand()
    end
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
    Logger.metadata(stage: "enqueue")
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
            Logger.info("[oban.DownloadWorker] enqueued processing: processing_job_id=#{processing_job.id} model=#{model}")
            :ok

          {:error, reason} ->
            Logger.error(
              "[oban.DownloadWorker] failed to enqueue processing worker for track #{track_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("[oban.DownloadWorker] failed to create processing job for track #{track_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp broadcast_progress(job_id, status, progress) do
    Logger.debug("[oban.DownloadWorker] broadcast jobs:#{job_id} status=#{status} progress=#{progress}")
    PipelineBroadcaster.broadcast_progress(job_id, status, progress)
  end

  defp broadcast_track_progress(track_id, stage, status, progress) do
    Logger.debug("[oban.DownloadWorker] broadcast track_pipeline:#{track_id} stage=#{stage} status=#{status} progress=#{progress}")
    PipelineBroadcaster.broadcast_track_progress(track_id, stage, status, progress)
  end
end
