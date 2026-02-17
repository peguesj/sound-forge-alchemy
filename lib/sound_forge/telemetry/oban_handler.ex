defmodule SoundForge.Telemetry.ObanHandler do
  @moduledoc """
  Telemetry handler for Oban job lifecycle events.

  Provides structured logging with namespace-scoped prefixes for every Oban job
  lifecycle stage (start, stop, exception). Sets Logger.metadata with oban-specific
  keys so downstream log formatters and backends can filter and correlate events.

  Also broadcasts pipeline failure events via PubSub so the dashboard can show
  errors in real-time.
  """
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    events = [
      [:oban, :job, :start],
      [:oban, :job, :stop],
      [:oban, :job, :exception]
    ]

    :telemetry.attach_many("oban-job-handler", events, &__MODULE__.handle_event/4, nil)
    {:ok, %{}}
  end

  @doc false
  def handle_event([:oban, :job, :start], _measurements, meta, _config) do
    job = meta.job
    short_worker = short_name(job.worker)

    set_oban_metadata(job)

    args_info = extract_args_info(job.args)

    Logger.info(
      "[oban.#{short_worker}] job:start job_id=#{job.id} queue=#{job.queue} attempt=#{job.attempt}#{args_info}"
    )

    :telemetry.execute(
      [:sound_forge, :oban, :job, :start],
      %{count: 1},
      %{worker: job.worker, queue: job.queue}
    )
  end

  def handle_event([:oban, :job, :stop], measurements, meta, _config) do
    job = meta.job
    short_worker = short_name(job.worker)
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    set_oban_metadata(job)

    result = if meta[:state] == :failure, do: "error", else: "ok"
    status = Map.get(meta, :state, :completed)

    Logger.info(
      "[oban.#{short_worker}] job:stop job_id=#{job.id} queue=#{job.queue} duration_ms=#{duration_ms} result=#{result} status=#{status}"
    )

    :telemetry.execute(
      [:sound_forge, :oban, :job, :stop],
      %{duration_ms: duration_ms, count: 1},
      %{worker: job.worker, queue: job.queue}
    )
  end

  def handle_event([:oban, :job, :exception], measurements, meta, _config) do
    job = meta.job
    short_worker = short_name(job.worker)
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    set_oban_metadata(job)

    {exception_module, exception_message} = format_exception(meta)
    stacktrace = format_stacktrace(meta)

    Logger.error(
      "[oban.#{short_worker}] job:exception job_id=#{job.id} queue=#{job.queue} " <>
        "attempt=#{job.attempt}/#{job.max_attempts} duration_ms=#{duration_ms} " <>
        "exception=#{exception_module} message=#{exception_message}" <>
        stacktrace
    )

    :telemetry.execute(
      [:sound_forge, :oban, :job, :exception],
      %{duration_ms: duration_ms, count: 1},
      %{worker: job.worker, queue: job.queue, attempt: job.attempt}
    )

    broadcast_pipeline_failure(job)
  end

  # -- Private --

  defp set_oban_metadata(job) do
    Logger.metadata(
      oban_job_id: job.id,
      oban_queue: job.queue,
      oban_worker: job.worker,
      oban_attempt: job.attempt
    )
  end

  defp short_name(worker) when is_binary(worker) do
    worker |> String.split(".") |> List.last()
  end

  defp short_name(worker), do: inspect(worker)

  defp extract_args_info(args) when is_map(args) do
    parts =
      Enum.flat_map(["track_id", "spotify_url"], fn key ->
        case Map.get(args, key) do
          nil -> []
          val -> [" #{key}=#{val}"]
        end
      end)

    Enum.join(parts)
  end

  defp extract_args_info(_), do: ""

  defp format_exception(%{kind: :error, reason: %{__struct__: mod} = reason}) do
    {inspect(mod), Exception.message(reason)}
  end

  defp format_exception(%{kind: :error, reason: reason}) do
    {"(non-exception)", inspect(reason)}
  end

  defp format_exception(%{reason: %{__struct__: mod} = reason}) do
    {inspect(mod), Exception.message(reason)}
  end

  defp format_exception(%{reason: reason}) do
    {"(unknown)", inspect(reason)}
  end

  defp format_exception(_), do: {"(unknown)", "(no reason)"}

  defp format_stacktrace(%{stacktrace: stacktrace}) when is_list(stacktrace) do
    frames =
      stacktrace
      |> Enum.take(5)
      |> Enum.map_join("\n    ", &Exception.format_stacktrace_entry/1)

    "\n  stacktrace:\n    #{frames}"
  end

  defp format_stacktrace(_), do: ""

  defp broadcast_pipeline_failure(%{worker: worker, args: args}) do
    track_id = args["track_id"]

    if track_id do
      stage = worker_to_stage(worker)

      if stage do
        Phoenix.PubSub.broadcast(
          SoundForge.PubSub,
          "track_pipeline:#{track_id}",
          {:pipeline_progress, %{track_id: track_id, stage: stage, status: :failed, progress: 0}}
        )
      end
    end
  end

  defp worker_to_stage("SoundForge.Jobs.DownloadWorker"), do: :download
  defp worker_to_stage("SoundForge.Jobs.ProcessingWorker"), do: :processing
  defp worker_to_stage("SoundForge.Jobs.AnalysisWorker"), do: :analysis
  defp worker_to_stage(_), do: nil
end
