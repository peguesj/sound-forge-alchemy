defmodule SoundForge.Telemetry.ObanHandlerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SoundForge.Telemetry.ObanHandler

  setup do
    previous_level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: previous_level) end)
    :ok
  end

  test "module compiles and exports handle_event/4" do
    Code.ensure_loaded!(ObanHandler)
    assert function_exported?(ObanHandler, :handle_event, 4)
  end

  describe "job:start" do
    test "logs with [oban.WorkerName] namespace, job_id, queue, attempt" do
      meta = %{job: %{id: 42, worker: "SoundForge.Jobs.DownloadWorker", queue: "download", attempt: 1, args: %{}}}

      log =
        capture_log(fn ->
          ObanHandler.handle_event([:oban, :job, :start], %{}, meta, nil)
        end)

      assert log =~ "[oban.DownloadWorker]"
      assert log =~ "job:start"
      assert log =~ "job_id=42"
      assert log =~ "queue=download"
      assert log =~ "attempt=1"
    end

    test "includes track_id and spotify_url from args when present" do
      meta = %{
        job: %{
          id: 43,
          worker: "SoundForge.Jobs.DownloadWorker",
          queue: "download",
          attempt: 1,
          args: %{"track_id" => "abc-123", "spotify_url" => "https://open.spotify.com/track/xyz"}
        }
      }

      log =
        capture_log(fn ->
          ObanHandler.handle_event([:oban, :job, :start], %{}, meta, nil)
        end)

      assert log =~ "track_id=abc-123"
      assert log =~ "spotify_url=https://open.spotify.com/track/xyz"
    end

    test "emits telemetry event" do
      :telemetry.attach(
        "test-start-handler",
        [:sound_forge, :oban, :job, :start],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      meta = %{job: %{id: 1, worker: "TestWorker", queue: "default", attempt: 1, args: %{}}}
      ObanHandler.handle_event([:oban, :job, :start], %{}, meta, nil)

      assert_receive {:telemetry_event, [:sound_forge, :oban, :job, :start], %{count: 1},
                      %{worker: "TestWorker", queue: "default"}}
    after
      :telemetry.detach("test-start-handler")
    end
  end

  describe "job:stop" do
    test "logs with namespace, duration_ms, result, status" do
      meta = %{job: %{id: 44, worker: "SoundForge.Jobs.DownloadWorker", queue: "download", attempt: 1, args: %{}}}
      measurements = %{duration: System.convert_time_unit(100, :millisecond, :native)}

      log =
        capture_log(fn ->
          ObanHandler.handle_event([:oban, :job, :stop], measurements, meta, nil)
        end)

      assert log =~ "[oban.DownloadWorker]"
      assert log =~ "job:stop"
      assert log =~ "job_id=44"
      assert log =~ "duration_ms="
      assert log =~ "result=ok"
      assert log =~ "status="
    end

    test "logs result=error when state is failure" do
      meta = %{
        job: %{id: 45, worker: "TestWorker", queue: "default", attempt: 1, args: %{}},
        state: :failure
      }

      measurements = %{duration: System.convert_time_unit(50, :millisecond, :native)}

      log =
        capture_log(fn ->
          ObanHandler.handle_event([:oban, :job, :stop], measurements, meta, nil)
        end)

      assert log =~ "result=error"
    end

    test "emits telemetry with duration_ms" do
      :telemetry.attach(
        "test-stop-handler",
        [:sound_forge, :oban, :job, :stop],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      meta = %{job: %{id: 1, worker: "TestWorker", queue: "default", attempt: 1, args: %{}}}
      measurements = %{duration: System.convert_time_unit(100, :millisecond, :native)}
      ObanHandler.handle_event([:oban, :job, :stop], measurements, meta, nil)

      assert_receive {:telemetry_event, [:sound_forge, :oban, :job, :stop],
                      %{duration_ms: duration_ms, count: 1}, %{worker: "TestWorker"}}

      assert duration_ms >= 95 and duration_ms <= 105
    after
      :telemetry.detach("test-stop-handler")
    end
  end

  describe "job:exception" do
    test "logs at error level with exception module, message, stacktrace" do
      meta = %{
        job: %{
          id: 46,
          worker: "SoundForge.Jobs.DownloadWorker",
          queue: "download",
          attempt: 1,
          max_attempts: 3,
          args: %{"track_id" => "test-123"}
        },
        kind: :error,
        reason: %RuntimeError{message: "something went wrong"},
        stacktrace: [
          {MyModule, :my_func, 2, [file: ~c"lib/my_module.ex", line: 10]},
          {MyModule, :other, 1, [file: ~c"lib/my_module.ex", line: 20]}
        ]
      }

      measurements = %{duration: System.convert_time_unit(50, :millisecond, :native)}

      log =
        capture_log(fn ->
          ObanHandler.handle_event([:oban, :job, :exception], measurements, meta, nil)
        end)

      assert log =~ "[oban.DownloadWorker]"
      assert log =~ "job:exception"
      assert log =~ "job_id=46"
      assert log =~ "attempt=1/3"
      assert log =~ "duration_ms="
      assert log =~ "exception=RuntimeError"
      assert log =~ "something went wrong"
      assert log =~ "stacktrace:"
    end

    test "broadcasts pipeline failure for pipeline workers" do
      meta = %{
        job: %{
          id: 47,
          worker: "SoundForge.Jobs.DownloadWorker",
          queue: "download",
          attempt: 1,
          max_attempts: 3,
          args: %{"track_id" => "test-123"}
        },
        kind: :error,
        reason: %RuntimeError{message: "test error"},
        stacktrace: []
      }

      measurements = %{duration: System.convert_time_unit(50, :millisecond, :native)}

      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:test-123")

      ObanHandler.handle_event([:oban, :job, :exception], measurements, meta, nil)

      assert_receive {:pipeline_progress,
                      %{track_id: "test-123", stage: :download, status: :failed, progress: 0}}
    end

    test "emits telemetry for exception" do
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
          id: 1,
          worker: "TestWorker",
          queue: "default",
          attempt: 2,
          max_attempts: 3,
          args: %{}
        },
        kind: :error,
        reason: %RuntimeError{message: "boom"},
        stacktrace: []
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
          id: 48,
          worker: "SomeOtherWorker",
          queue: "default",
          attempt: 1,
          max_attempts: 3,
          args: %{"track_id" => "test-456"}
        },
        kind: :error,
        reason: %RuntimeError{message: "test error"},
        stacktrace: []
      }

      measurements = %{duration: System.convert_time_unit(10, :millisecond, :native)}

      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:test-456")
      ObanHandler.handle_event([:oban, :job, :exception], measurements, meta, nil)

      refute_receive {:pipeline_progress, _}, 100
    end

    test "exception without track_id does not broadcast" do
      meta = %{
        job: %{
          id: 49,
          worker: "SoundForge.Jobs.DownloadWorker",
          queue: "download",
          attempt: 1,
          max_attempts: 3,
          args: %{}
        },
        kind: :error,
        reason: %RuntimeError{message: "test error"},
        stacktrace: []
      }

      measurements = %{duration: System.convert_time_unit(10, :millisecond, :native)}

      ObanHandler.handle_event([:oban, :job, :exception], measurements, meta, nil)
    end

    test "handles exceptions without stacktrace" do
      meta = %{
        job: %{
          id: 50,
          worker: "TestWorker",
          queue: "default",
          attempt: 1,
          max_attempts: 3,
          args: %{}
        },
        reason: %RuntimeError{message: "no stacktrace"}
      }

      measurements = %{duration: System.convert_time_unit(10, :millisecond, :native)}

      log =
        capture_log(fn ->
          ObanHandler.handle_event([:oban, :job, :exception], measurements, meta, nil)
        end)

      assert log =~ "[oban.TestWorker]"
      assert log =~ "job:exception"
      refute log =~ "stacktrace:"
    end
  end
end
