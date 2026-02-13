defmodule SoundForge.Telemetry.ObanHandlerTest do
  use ExUnit.Case, async: true

  alias SoundForge.Telemetry.ObanHandler

  test "module compiles and exports handle_event/4" do
    Code.ensure_loaded!(ObanHandler)
    assert function_exported?(ObanHandler, :handle_event, 4)
  end

  test "handle_event processes job start without error" do
    meta = %{job: %{worker: "TestWorker", queue: "default"}}
    assert ObanHandler.handle_event([:oban, :job, :start], %{}, meta, nil) == :ok
  end

  test "handle_event processes job stop without error" do
    meta = %{job: %{worker: "TestWorker", queue: "default"}}
    measurements = %{duration: System.convert_time_unit(100, :millisecond, :native)}
    assert ObanHandler.handle_event([:oban, :job, :stop], measurements, meta, nil) == :ok
  end

  test "handle_event processes job exception and broadcasts pipeline failure" do
    meta = %{
      job: %{
        worker: "SoundForge.Jobs.DownloadWorker",
        queue: "download",
        attempt: 1,
        max_attempts: 3,
        args: %{"track_id" => "test-123"}
      },
      reason: %RuntimeError{message: "test error"}
    }

    measurements = %{duration: System.convert_time_unit(50, :millisecond, :native)}

    # Subscribe to track pipeline to verify broadcast
    Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:test-123")

    ObanHandler.handle_event([:oban, :job, :exception], measurements, meta, nil)

    assert_receive {:pipeline_progress,
                    %{track_id: "test-123", stage: :download, status: :failed, progress: 0}}
  end

  test "handle_event emits telemetry for job start" do
    :telemetry.attach(
      "test-start-handler",
      [:sound_forge, :oban, :job, :start],
      fn event, measurements, metadata, _config ->
        send(self(), {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    meta = %{job: %{worker: "TestWorker", queue: "default"}}
    ObanHandler.handle_event([:oban, :job, :start], %{}, meta, nil)

    assert_receive {:telemetry_event, [:sound_forge, :oban, :job, :start], %{count: 1},
                    %{worker: "TestWorker", queue: "default"}}
  after
    :telemetry.detach("test-start-handler")
  end

  test "handle_event emits telemetry for job stop with duration" do
    :telemetry.attach(
      "test-stop-handler",
      [:sound_forge, :oban, :job, :stop],
      fn event, measurements, metadata, _config ->
        send(self(), {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    meta = %{job: %{worker: "TestWorker", queue: "default"}}
    measurements = %{duration: System.convert_time_unit(100, :millisecond, :native)}
    ObanHandler.handle_event([:oban, :job, :stop], measurements, meta, nil)

    assert_receive {:telemetry_event, [:sound_forge, :oban, :job, :stop],
                    %{duration_ms: duration_ms, count: 1}, %{worker: "TestWorker"}}

    assert duration_ms >= 95 and duration_ms <= 105
  after
    :telemetry.detach("test-stop-handler")
  end

  test "handle_event emits telemetry for job exception" do
    :telemetry.attach(
      "test-exception-handler",
      [:sound_forge, :oban, :job, :exception],
      fn event, measurements, metadata, _config ->
        send(self(), {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    meta = %{
      job: %{
        worker: "TestWorker",
        queue: "default",
        attempt: 2,
        max_attempts: 3,
        args: %{}
      },
      reason: %RuntimeError{message: "boom"}
    }

    measurements = %{duration: System.convert_time_unit(50, :millisecond, :native)}
    ObanHandler.handle_event([:oban, :job, :exception], measurements, meta, nil)

    assert_receive {:telemetry_event, [:sound_forge, :oban, :job, :exception],
                    %{duration_ms: _, count: 1}, %{worker: "TestWorker", attempt: 2}}
  after
    :telemetry.detach("test-exception-handler")
  end

  test "non-pipeline worker exception does not broadcast pipeline event" do
    meta = %{
      job: %{
        worker: "SomeOtherWorker",
        queue: "default",
        attempt: 1,
        max_attempts: 3,
        args: %{"track_id" => "test-456"}
      },
      reason: %RuntimeError{message: "test error"}
    }

    measurements = %{duration: System.convert_time_unit(10, :millisecond, :native)}

    Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:test-456")
    ObanHandler.handle_event([:oban, :job, :exception], measurements, meta, nil)

    refute_receive {:pipeline_progress, _}, 100
  end

  test "exception without track_id does not broadcast" do
    meta = %{
      job: %{
        worker: "SoundForge.Jobs.DownloadWorker",
        queue: "download",
        attempt: 1,
        max_attempts: 3,
        args: %{}
      },
      reason: %RuntimeError{message: "test error"}
    }

    measurements = %{duration: System.convert_time_unit(10, :millisecond, :native)}

    # Should not crash even without track_id
    ObanHandler.handle_event([:oban, :job, :exception], measurements, meta, nil)
  end
end
