defmodule SoundForge.Jobs.DemuserWorker do
  @moduledoc """
  Oban worker for demuser-based voice+music separation using the lalal.ai API.

  Uploads a track's audio file to lalal.ai via the v1.1 upload endpoint,
  initiates a demuser split (which separates voice from background music),
  polls for completion with exponential backoff, downloads both stem files,
  creates Stem records, and chains the AnalysisWorker on completion.

  ## Demuser Output

  The demuser engine produces two tracks:
  - **stem** (label: "music") - The background music/instrumental track
  - **back** (label: "no_music") - The isolated voice track

  ## Job Arguments

    - `"track_id"` - UUID of the Track record
    - `"job_id"` - UUID of the ProcessingJob record
    - `"file_path"` - Relative or absolute path to the audio file
    - `"splitter"` - lalal.ai model name (default: "phoenix")
    - `"dereverb"` - Boolean, enable de-reverb (default: false)
    - `"encoder_format"` - Output format (default: "wav")

  ## Pipeline

  The worker progresses through these stages:
  1. `:queued` -> `:processing` (upload started)
  2. Progress broadcasts as lalal.ai processes (0-90%)
  3. `:completed` on success with both stems downloaded
  4. Chains `AnalysisWorker` for audio feature extraction

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
          "file_path" => file_path
        } = args
      }) do
    Logger.metadata(track_id: track_id, job_id: job_id, worker: "DemuserWorker")

    splitter = Map.get(args, "splitter", "phoenix")
    dereverb = Map.get(args, "dereverb", false)
    encoder_format = Map.get(args, "encoder_format", "wav")

    Logger.info(
      "Starting demuser separation: splitter=#{splitter}, dereverb=#{dereverb}, format=#{encoder_format}"
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

    with {:ok, source_id} <- LalalAI.upload_source(resolved_path),
         _ <- Logger.info("lalal.ai source uploaded: #{source_id}"),
         _ <-
           (fresh_upload_job = Music.get_processing_job!(job_id);
            Music.update_processing_job(fresh_upload_job, %{
              options: Map.put(fresh_upload_job.options || %{}, "lalalai_source_id", source_id)
            })),
         {:ok, %{"task_id" => task_id}} <-
           LalalAI.split_demuser(source_id,
             splitter: splitter,
             dereverb: dereverb,
             encoder_format: encoder_format
           ),
         _ <- Logger.info("lalal.ai demuser task created: #{task_id}"),
         _ <-
           (fresh_split_job = Music.get_processing_job!(job_id);
            Music.update_processing_job(fresh_split_job, %{
              options: Map.put(fresh_split_job.options || %{}, "lalalai_task_id", task_id)
            })),
         {:ok, stem_urls} <- poll_until_complete(task_id, job_id, track_id) do
      process_completed_stems(
        track_id,
        job_id,
        file_path,
        stem_urls,
        splitter,
        encoder_format
      )
    else
      {:error, reason} ->
        error_msg = inspect(reason)
        Logger.error("lalal.ai demuser separation failed: #{error_msg}")
        fresh_job = Music.get_processing_job!(job_id)
        Music.update_processing_job(fresh_job, %{status: :failed, error: error_msg})
        PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :processing)
        {:error, error_msg}
    end
  end

  # -- Private --

  defp poll_until_complete(task_id, job_id, track_id) do
    poll_until_complete(task_id, job_id, track_id, 0, @initial_poll_interval_ms)
  end

  defp poll_until_complete(_task_id, job_id, track_id, attempt, _interval)
       when attempt >= @max_poll_attempts do
    Logger.error("lalal.ai demuser polling timed out after #{attempt} attempts")
    fresh_job = Music.get_processing_job!(job_id)
    Music.update_processing_job(fresh_job, %{status: :failed, error: "Polling timeout"})
    PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :processing)
    {:error, :polling_timeout}
  end

  defp poll_until_complete(task_id, job_id, track_id, attempt, interval) do
    :timer.sleep(interval)

    case LalalAI.get_status(task_id) do
      {:ok, %{status: "success", stem: stem, back: back}} ->
        Logger.info("lalal.ai demuser task #{task_id} completed successfully")
        {:ok, %{task_id: task_id, stem: stem, back: back}}

      {:ok, %{status: "progress", queue_progress: queue_progress}} ->
        # Map queue_progress (0-100) to 10-90% of our progress bar
        progress = if queue_progress, do: trunc(10 + queue_progress * 0.8), else: 20 + attempt

        fresh_job = Music.get_processing_job!(job_id)
        Music.update_processing_job(fresh_job, %{progress: min(progress, 90)})
        broadcast_progress(job_id, :processing, min(progress, 90))

        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:ok, %{status: "queued"}} ->
        Logger.debug("lalal.ai demuser task #{task_id} still queued (attempt #{attempt})")
        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:ok, %{status: "error", error: error_message}} ->
        Logger.error("lalal.ai demuser task #{task_id} failed: #{error_message}")
        {:error, {:lalalai_error, error_message}}

      {:ok, %{status: unknown_status}} ->
        Logger.warning("lalal.ai demuser task #{task_id} unknown status: #{unknown_status}")
        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:error, reason} ->
        Logger.warning(
          "lalal.ai demuser status check failed (attempt #{attempt}): #{inspect(reason)}, retrying..."
        )

        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)
    end
  end

  defp process_completed_stems(track_id, job_id, file_path, stem_urls, splitter, encoder_format) do
    stem_dir = build_stem_dir(track_id)
    File.mkdir_p!(stem_dir)

    ext = if encoder_format in ["mp3", "flac", "ogg"], do: encoder_format, else: "wav"

    # Download the music stem (the "stem" output from demuser = instrumental/music)
    music_stems =
      case Map.get(stem_urls, :stem) do
        %{"link" => download_url} when is_binary(download_url) ->
          stem_path = Path.join(stem_dir, "music.#{ext}")

          case LalalAI.download_stem(download_url, stem_path) do
            {:ok, saved_path} ->
              relative_path = make_relative(saved_path)

              persist_stem(track_id, job_id, :other, saved_path, relative_path, %{
                "label" => "music",
                "mode" => "demuser"
              })

            {:error, reason} ->
              Logger.error("Failed to download music stem: #{inspect(reason)}")
              []
          end

        _ ->
          Logger.warning("No download link in lalal.ai demuser stem result")
          []
      end

    # Download the no_music back track (the "back" output from demuser = voice/no_music)
    no_music_stems =
      case Map.get(stem_urls, :back) do
        %{"link" => download_url} when is_binary(download_url) ->
          back_path = Path.join(stem_dir, "no_music.#{ext}")

          case LalalAI.download_stem(download_url, back_path) do
            {:ok, saved_path} ->
              relative_path = make_relative(saved_path)

              persist_stem(track_id, job_id, :vocals, saved_path, relative_path, %{
                "label" => "no_music",
                "mode" => "demuser"
              })

            {:error, reason} ->
              Logger.error("Failed to download no_music back track: #{inspect(reason)}")
              []
          end

        _ ->
          Logger.warning("No download link in lalal.ai demuser back result")
          []
      end

    stem_records = music_stems ++ no_music_stems

    fresh_job = Music.get_processing_job!(job_id)

    job_options =
      Map.merge(fresh_job.options || %{}, %{
        "engine" => "lalalai",
        "mode" => "demuser",
        "splitter" => splitter,
        "encoder_format" => encoder_format
      })

    Music.update_processing_job(fresh_job, %{
      status: :completed,
      progress: 100,
      output_path: stem_dir,
      options: job_options
    })

    Logger.info("lalal.ai demuser separation complete, stems=#{length(stem_records)}")
    PipelineBroadcaster.broadcast_stage_complete(track_id, job_id, :processing)

    # Chain: enqueue analysis job
    enqueue_analysis(track_id, file_path)

    {:ok, %{stems: length(stem_records)}}
  end

  defp persist_stem(track_id, job_id, stem_type_atom, _absolute_path, relative_path, _options) do
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
