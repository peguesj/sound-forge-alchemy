defmodule SoundForge.Debug.LogBroadcasterTest do
  use ExUnit.Case, async: false

  alias SoundForge.Debug.LogBroadcaster

  describe "topic/0" do
    test "returns the debug logs topic" do
      assert LogBroadcaster.topic() == "debug:logs"
    end
  end

  describe "init/1" do
    test "returns ok with empty state" do
      assert {:ok, %{}} = LogBroadcaster.init([])
    end
  end

  describe "handle_event/2" do
    setup do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, LogBroadcaster.topic())
      :ok
    end

    test "broadcasts log events with level, message, timestamp, metadata, and namespace" do
      timestamp = {{2026, 2, 17}, {10, 30, 45, 123}}
      metadata = [request_id: "abc123", oban_job_id: 42]

      LogBroadcaster.handle_event(
        {:info, self(), {Logger, "[oban.DownloadWorker] job:start job_id=42", timestamp, metadata}},
        %{}
      )

      assert_receive {:debug_log, event}
      assert event.level == :info
      assert event.message == "[oban.DownloadWorker] job:start job_id=42"
      assert event.namespace == "oban.DownloadWorker"
      assert event.timestamp == "2026-02-17 10:30:45.123"
      assert event.metadata.request_id == "abc123"
      assert event.metadata.oban_job_id == 42
    end

    test "extracts nil namespace when no bracket prefix" do
      timestamp = {{2026, 2, 17}, {10, 30, 45, 0}}

      LogBroadcaster.handle_event(
        {:debug, self(), {Logger, "plain log message", timestamp, []}},
        %{}
      )

      assert_receive {:debug_log, event}
      assert event.namespace == nil
      assert event.message == "plain log message"
    end

    test "handles flush event" do
      assert {:ok, %{}} = LogBroadcaster.handle_event(:flush, %{})
    end

    test "handles unknown events" do
      assert {:ok, %{}} = LogBroadcaster.handle_event(:unknown, %{})
    end
  end
end
