defmodule SoundForgeWeb.JobChannelTest do
  use SoundForgeWeb.ChannelCase

  setup do
    {:ok, _, socket} =
      SoundForgeWeb.UserSocket
      |> socket()
      |> subscribe_and_join(SoundForgeWeb.JobChannel, "jobs:test-job-123")

    %{socket: socket}
  end

  test "joins successfully", %{socket: socket} do
    assert socket.assigns.job_id == "test-job-123"
  end

  test "receives job:progress from PubSub", %{socket: _socket} do
    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "jobs:test-job-123",
      {:job_progress, %{job_id: "test-job-123", status: "downloading", progress: 50}}
    )

    assert_push "job:progress", %{job_id: "test-job-123", progress: 50}
  end

  test "receives job:completed from PubSub", %{socket: _socket} do
    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "jobs:test-job-123",
      {:job_completed, %{job_id: "test-job-123", status: "completed"}}
    )

    assert_push "job:completed", %{job_id: "test-job-123", status: "completed"}
  end

  test "receives job:failed from PubSub", %{socket: _socket} do
    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "jobs:test-job-123",
      {:job_failed, %{job_id: "test-job-123", error: "Download failed"}}
    )

    assert_push "job:failed", %{error: "Download failed"}
  end

  test "receives pipeline:complete from PubSub", %{socket: _socket} do
    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "jobs:test-job-123",
      {:pipeline_complete, %{track_id: "track-abc"}}
    )

    assert_push "pipeline:complete", %{track_id: "track-abc"}
  end

  test "receives pipeline:progress from PubSub", %{socket: _socket} do
    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "jobs:test-job-123",
      {:pipeline_progress, %{track_id: "track-abc", stage: :processing, status: :processing, progress: 50}}
    )

    assert_push "pipeline:progress", %{track_id: "track-abc", progress: 50}
  end
end
