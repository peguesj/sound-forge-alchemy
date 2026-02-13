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
end
