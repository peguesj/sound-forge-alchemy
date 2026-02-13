defmodule SoundForge.Telemetry.ObanHandler do
  @moduledoc """
  Telemetry handler for Oban job lifecycle events.

  Tracks job execution duration, success/failure rates, and broadcasts
  pipeline failure events so the dashboard can show errors in real-time.
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
    Logger.info("Oban job started: #{meta.job.worker} (queue: #{meta.job.queue})")

    :telemetry.execute(
      [:sound_forge, :oban, :job, :start],
      %{count: 1},
      %{worker: meta.job.worker, queue: meta.job.queue}
    )
  end

  def handle_event([:oban, :job, :stop], measurements, meta, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info(
      "Oban job completed: #{meta.job.worker} in #{duration_ms}ms (queue: #{meta.job.queue})"
    )

    :telemetry.execute(
      [:sound_forge, :oban, :job, :stop],
      %{duration_ms: duration_ms, count: 1},
      %{worker: meta.job.worker, queue: meta.job.queue}
    )
  end

  def handle_event([:oban, :job, :exception], measurements, meta, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error(
      "Oban job failed: #{meta.job.worker} after #{duration_ms}ms - #{inspect(meta.reason)} (attempt #{meta.job.attempt}/#{meta.job.max_attempts})"
    )

    :telemetry.execute(
      [:sound_forge, :oban, :job, :exception],
      %{duration_ms: duration_ms, count: 1},
      %{worker: meta.job.worker, queue: meta.job.queue, attempt: meta.job.attempt}
    )

    # Broadcast pipeline failure if this is one of our pipeline workers
    broadcast_pipeline_failure(meta.job)
  end

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
