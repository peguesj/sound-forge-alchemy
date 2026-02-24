defmodule SoundForge.Jobs.VoiceChangeWorker do
  @moduledoc """
  Oban worker for voice change processing using the lalal.ai API.

  Uploads a track's audio file to lalal.ai, applies a voice pack transformation,
  polls for completion with exponential backoff, downloads the result to the local
  stems directory, creates a Stem record with stem_type :vocals, and refreshes
  the voice pack cache when stale.

  ## Job Arguments

    - `"track_id"` - UUID of the Track record
    - `"job_id"` - UUID of the ProcessingJob record
    - `"file_path"` - Relative or absolute path to the audio file
    - `"voice_pack_id"` - UUID or builtin name of the voice pack to apply
    - `"accent"` - Float from 0.0 to 1.0 controlling accent intensity (default: 0.5)
    - `"tonality_reference"` - `"source_file"` or `"voice_pack"` (default: "source_file")
    - `"dereverb"` - Boolean, enable de-reverb (default: false)
    - `"encoder_format"` - Output format (default: "wav")

  ## Pipeline

  The worker progresses through these stages:
  1. `:queued` -> `:processing` (upload started)
  2. Progress broadcasts as lalal.ai processes (0-90%)
  3. `:completed` on success with voice-changed stem downloaded
  4. Voice pack cache refreshed if older than 1 hour
  """
  use Oban.Worker,
    queue: :processing,
    max_attempts: 3,
    priority: 2

  alias SoundForge.Audio.LalalAI
  alias SoundForge.Audio.VoicePack
  alias SoundForge.Jobs.PipelineBroadcaster
  alias SoundForge.Music
  alias SoundForge.Repo

  import Ecto.Query, warn: false

  require Logger

  # Poll interval: start at 5 seconds, max 60 seconds
  @initial_poll_interval_ms 5_000
  @max_poll_interval_ms 60_000
  # Maximum total polling time: 20 minutes
  @max_poll_attempts 120
  # Voice pack cache TTL: 1 hour
  @cache_ttl_seconds 3_600

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "track_id" => track_id,
          "job_id" => job_id,
          "file_path" => file_path
        } = args
      }) do
    Logger.metadata(track_id: track_id, job_id: job_id, worker: "VoiceChangeWorker")

    voice_pack_id = Map.fetch!(args, "voice_pack_id")
    accent = Map.get(args, "accent", 0.5)
    tonality_reference = Map.get(args, "tonality_reference", "source_file")
    dereverb = Map.get(args, "dereverb", false)
    encoder_format = Map.get(args, "encoder_format", "wav")

    Logger.info(
      "Starting voice change: voice_pack=#{voice_pack_id}, accent=#{accent}, " <>
        "tonality=#{tonality_reference}, dereverb=#{dereverb}"
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

    with {:ok, source_id} <- LalalAI.upload_track(resolved_path),
         _ <- Logger.info("lalal.ai upload complete, source_id=#{source_id}"),
         _ <- broadcast_progress(job_id, :processing, 10),
         _ <-
           (fresh_upload_job = Music.get_processing_job!(job_id);
            Music.update_processing_job(fresh_upload_job, %{
              options: Map.put(fresh_upload_job.options || %{}, "lalalai_source_id", source_id)
            })),
         {:ok, _change_result} <-
           LalalAI.change_voice(source_id,
             voice_pack_id: voice_pack_id,
             accent: accent,
             tonality_reference: tonality_reference,
             dereverb: dereverb,
             encoder_format: encoder_format
           ),
         _ <- Logger.info("lalal.ai voice change initiated for source #{source_id}"),
         {:ok, stem_urls} <- poll_until_complete(source_id, job_id, track_id) do
      result =
        process_completed_voice_change(
          track_id,
          job_id,
          stem_urls,
          voice_pack_id,
          accent,
          tonality_reference,
          encoder_format
        )

      maybe_refresh_voice_pack_cache()

      result
    else
      {:error, reason} ->
        error_msg = inspect(reason)
        Logger.error("Voice change failed: #{error_msg}")
        fresh_job = Music.get_processing_job!(job_id)
        Music.update_processing_job(fresh_job, %{status: :failed, error: error_msg})
        PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :processing)
        {:error, error_msg}
    end
  end

  # -- Private: Polling --

  defp poll_until_complete(task_id, job_id, track_id) do
    poll_until_complete(task_id, job_id, track_id, 0, @initial_poll_interval_ms)
  end

  defp poll_until_complete(_task_id, job_id, track_id, attempt, _interval)
       when attempt >= @max_poll_attempts do
    Logger.error("Voice change polling timed out after #{attempt} attempts")
    fresh_job = Music.get_processing_job!(job_id)
    Music.update_processing_job(fresh_job, %{status: :failed, error: "Polling timeout"})
    PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :processing)
    {:error, :polling_timeout}
  end

  defp poll_until_complete(task_id, job_id, track_id, attempt, interval) do
    :timer.sleep(interval)

    case LalalAI.get_status(task_id) do
      {:ok, %{status: "success", stem: stem, accompaniment: _accompaniment}} ->
        Logger.info("Voice change task #{task_id} completed successfully")
        {:ok, %{task_id: task_id, stem: stem}}

      {:ok, %{status: "progress", queue_progress: queue_progress}} ->
        progress = if queue_progress, do: trunc(10 + queue_progress * 0.8), else: 20 + attempt

        fresh_job = Music.get_processing_job!(job_id)
        Music.update_processing_job(fresh_job, %{progress: min(progress, 90)})
        broadcast_progress(job_id, :processing, min(progress, 90))

        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:ok, %{status: "queued"}} ->
        Logger.debug("Voice change task #{task_id} still queued (attempt #{attempt})")
        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:ok, %{status: "error", error: error_message}} ->
        Logger.error("Voice change task #{task_id} failed: #{error_message}")
        {:error, {:lalalai_error, error_message}}

      {:ok, %{status: unknown_status}} ->
        Logger.warning("Voice change task #{task_id} unknown status: #{unknown_status}")
        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)

      {:error, reason} ->
        Logger.warning(
          "Voice change status check failed (attempt #{attempt}): #{inspect(reason)}, retrying..."
        )

        next_interval = min(interval * 2, @max_poll_interval_ms)
        poll_until_complete(task_id, job_id, track_id, attempt + 1, next_interval)
    end
  end

  # -- Private: Result Processing --

  defp process_completed_voice_change(
         track_id,
         job_id,
         stem_urls,
         voice_pack_id,
         accent,
         tonality_reference,
         encoder_format
       ) do
    stem_dir = build_stem_dir(track_id)
    File.mkdir_p!(stem_dir)

    stem_records =
      case Map.get(stem_urls, :stem) do
        %{"link" => download_url} when is_binary(download_url) ->
          stem_filename = "voice_changed.#{encoder_format}"
          stem_path = Path.join(stem_dir, stem_filename)

          case LalalAI.download_stem(download_url, stem_path) do
            {:ok, saved_path} ->
              relative_path = make_relative(saved_path)
              persist_stem(track_id, job_id, saved_path, relative_path)

            {:error, reason} ->
              Logger.error("Failed to download voice-changed stem: #{inspect(reason)}")
              []
          end

        _ ->
          Logger.warning("No download link in voice change result")
          []
      end

    fresh_job = Music.get_processing_job!(job_id)

    job_options =
      Map.merge(fresh_job.options || %{}, %{
        "engine" => "lalalai",
        "voice_changed" => true,
        "voice_pack_id" => voice_pack_id,
        "accent" => accent,
        "tonality_reference" => tonality_reference
      })

    Music.update_processing_job(fresh_job, %{
      status: :completed,
      progress: 100,
      output_path: stem_dir,
      options: job_options
    })

    Logger.info("Voice change complete, stems=#{length(stem_records)}")
    PipelineBroadcaster.broadcast_stage_complete(track_id, job_id, :processing)

    {:ok, %{stems: length(stem_records)}}
  end

  defp persist_stem(track_id, job_id, _absolute_path, relative_path) do
    file_size =
      case File.stat(relative_path) do
        {:ok, %{size: size}} -> size
        _ -> 0
      end

    case Music.create_stem(%{
           track_id: track_id,
           processing_job_id: job_id,
           stem_type: :vocals,
           file_path: relative_path,
           file_size: file_size,
           source: "voice_change"
         }) do
      {:ok, stem} ->
        [stem]

      {:error, reason} ->
        Logger.warning("Failed to create voice-changed stem record: #{inspect(reason)}")
        []
    end
  end

  # -- Private: Voice Pack Cache --

  defp maybe_refresh_voice_pack_cache do
    cutoff = DateTime.add(DateTime.utc_now(), -@cache_ttl_seconds, :second)

    oldest_cached =
      VoicePack
      |> select([vp], min(vp.cached_at))
      |> Repo.one()

    should_refresh =
      is_nil(oldest_cached) or DateTime.compare(oldest_cached, cutoff) == :lt

    if should_refresh do
      Logger.info("Voice pack cache is stale, refreshing from lalal.ai")
      refresh_voice_pack_cache()
    else
      Logger.debug("Voice pack cache is fresh, skipping refresh")
      :ok
    end
  end

  defp refresh_voice_pack_cache do
    case LalalAI.list_voice_packs() do
      {:ok, packs} when is_list(packs) ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Enum.each(packs, fn pack ->
          pack_id = Map.get(pack, "id") || Map.get(pack, "pack_id")
          name = Map.get(pack, "name", "Unknown")

          created_at_remote =
            case Map.get(pack, "created_at") do
              ts when is_binary(ts) ->
                case DateTime.from_iso8601(ts) do
                  {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
                  _ -> nil
                end

              _ ->
                nil
            end

          attrs = %{
            pack_id: pack_id,
            name: name,
            created_at_remote: created_at_remote,
            cached_at: now
          }

          case Repo.get_by(VoicePack, pack_id: pack_id) do
            nil ->
              %VoicePack{}
              |> VoicePack.changeset(attrs)
              |> Repo.insert()

            existing ->
              existing
              |> VoicePack.changeset(attrs)
              |> Repo.update()
          end
        end)

        Logger.info("Voice pack cache refreshed with #{length(packs)} packs")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to refresh voice pack cache: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # -- Private: Helpers --

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

  defp broadcast_progress(job_id, status, progress) do
    PipelineBroadcaster.broadcast_progress(job_id, status, progress)
  end

  defp broadcast_track_progress(track_id, stage, status, progress) do
    PipelineBroadcaster.broadcast_track_progress(track_id, stage, status, progress)
  end
end
