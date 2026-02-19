defmodule SoundForge.Jobs.LalalAIWorker do
  @moduledoc """
  Oban worker for cloud-based stem separation using the lalal.ai API.

  Uploads a track's audio file to lalal.ai, polls for completion with
  exponential backoff, downloads stem files to the local stems directory,
  creates Stem records for each separated stem, and chains the AnalysisWorker
  on successful completion.

  ## Job Arguments

    - `"track_id"` - UUID of the Track record
    - `"job_id"` - UUID of the ProcessingJob record
    - `"file_path"` - Relative or absolute path to the audio file
    - `"stem_filter"` - lalal.ai stem filter name (default: "vocals").
      See `SoundForge.Audio.LalalAI.stem_filters/0` for valid values.
    - `"preview"` - Boolean (default: false). If true, only processes first 60s.
      NOTE: Preview mode behavior is API-dependent; full separation is performed
      and results are stored with `preview: true` in the job options.
    - `"splitter"` - lalal.ai model name (default: "phoenix")

  ## Pipeline

  The worker progresses through these stages:
  1. `:queued` -> `:processing` (upload started)
  2. Progress broadcasts as lalal.ai processes (0-90%)
  3. `:completed` on success with stems downloaded
  4. Chains `AnalysisWorker` for audio feature extraction

  """
  use Oban.Worker,
    queue: :processing,
    max_attempts: 3,
    priority: 2

  alias SoundForge.Audio.LalalAI
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
    Logger.metadata(track_id: track_id, job_id: job_id, worker: "LalalAIWorker")

    stem_filter = Map.get(args, "stem_filter", "vocals")
    preview = Map.get(args, "preview", false)
    splitter = Map.get(args, "splitter", "phoenix")

    Logger.info(
      "Starting lalal.ai separation: filter=#{stem_filter}, preview=#{preview}, splitter=#{splitter}"
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
      broadcast_progress(job_id, :failed, 0)
      broadcast_track_progress(track_id, :processing, :failed, 0)
      raise error_msg
    end

    with {:ok, task_id} <-
           LalalAI.upload_track(resolved_path,
             stem_filter: stem_filter,
             splitter: splitter
           ),
         _ <- Logger.info("lalal.ai task created: #{task_id}"),
         {:ok, stem_urls} <- poll_until_complete(task_id, job_id, track_id) do
      process_completed_stems(
        track_id,
        job_id,
        file_path,
        stem_urls,
        stem_filter,
        preview
      )
    else
      {:error, reason} ->
        error_msg = inspect(reason)
        Logger.error("lalal.ai separation failed: #{error_msg}")
        fresh_job = Music.get_processing_job!(job_id)
        Music.update_processing_job(fresh_job, %{status: :failed, error: error_msg})
        broadcast_progress(job_id, :failed, 0)
        broadcast_track_progress(track_id, :processing, :failed, 0)
        {:error, error_msg}
    end
  end

  # -- Private --

  defp poll_until_complete(task_id, job_id, track_id) do
    poll_until_complete(task_id, job_id, track_id, 0, @initial_poll_interval_ms)
  end

  defp poll_until_complete(_task_id, job_id, track_id, attempt, _interval)
       when attempt >= @max_poll_attempts do
    Logger.error("lalal.ai polling timed out after #{attempt} attempts")
    fresh_job = Music.get_processing_job!(job_id)
    Music.update_processing_job(fresh_job, %{status: :failed, error: "Polling timeout"})
    broadcast_progress(job_id, :failed, 0)
    broadcast_track_progress(track_id, :processing, :failed, 0)
    {:error, :polling_timeout}
  end

  defp poll_until_complete(task_id, job_id, track_id, attempt, interval) do
    :timer.sleep(interval)

    case LalalAI.get_status(task_id) do
      {:ok, %{status: "success", stem: stem, accompaniment: _accompaniment}} ->
        Logger.info("lalal.ai task #{task_id} completed successfully")
        {:ok, %{task_id: task_id, stem: stem}}

      {:ok, %{status: "progress", queue_progress: queue_progress}} ->
        # Map queue_progress (0-100) to 10-90% of our progress bar
        progress = if queue_progress, do: trunc(10 + queue_progress * 0.8), else: 20 + attempt

        fresh_job = Music.get_processing_job!(job_id)
        Music.update_processing_job(fresh_job, %{progress: min(progress, 90)})
        broadcast_progress(job_id, :processing, min(progress, 90))

        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:ok, %{status: "queued"}} ->
        Logger.debug("lalal.ai task #{task_id} still queued (attempt #{attempt})")
        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:ok, %{status: "error", error: error_message}} ->
        Logger.error("lalal.ai task #{task_id} failed: #{error_message}")
        {:error, {:lalalai_error, error_message}}

      {:ok, %{status: unknown_status}} ->
        Logger.warning("lalal.ai task #{task_id} unknown status: #{unknown_status}")
        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:error, reason} ->
        Logger.warning(
          "lalal.ai status check failed (attempt #{attempt}): #{inspect(reason)}, retrying..."
        )

        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)
    end
  end

  defp process_completed_stems(track_id, job_id, file_path, stem_urls, stem_filter, preview) do
    stem_dir = build_stem_dir(track_id)
    File.mkdir_p!(stem_dir)

    stem_type_atom = LalalAI.filter_to_stem_type(stem_filter) || :other

    # Download the primary stem (the separated stem)
    stem_records =
      case Map.get(stem_urls, :stem) do
        %{"link" => download_url} when is_binary(download_url) ->
          stem_filename = "#{stem_filter}.wav"
          stem_path = Path.join(stem_dir, stem_filename)

          case LalalAI.download_stem(download_url, stem_path) do
            {:ok, saved_path} ->
              relative_path = make_relative(saved_path)
              persist_stem(track_id, job_id, stem_type_atom, saved_path, relative_path)

            {:error, reason} ->
              Logger.error("Failed to download stem #{stem_filter}: #{inspect(reason)}")
              []
          end

        _ ->
          Logger.warning("No download link in lalal.ai stem result")
          []
      end

    fresh_job = Music.get_processing_job!(job_id)

    job_options =
      Map.merge(fresh_job.options || %{}, %{
        "engine" => "lalalai",
        "stem_filter" => stem_filter,
        "preview" => preview
      })

    Music.update_processing_job(fresh_job, %{
      status: :completed,
      progress: 100,
      output_path: stem_dir,
      options: job_options
    })

    Logger.info("lalal.ai separation complete, stems=#{length(stem_records)}")
    broadcast_progress(job_id, :completed, 100)
    broadcast_track_progress(track_id, :processing, :completed, 100)

    # Chain: enqueue analysis job
    enqueue_analysis(track_id, file_path)

    {:ok, %{stems: length(stem_records)}}
  end

  defp persist_stem(track_id, job_id, stem_type_atom, _absolute_path, relative_path) do
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
           file_size: file_size
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
