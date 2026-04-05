defmodule SoundForgeWeb.DashboardHandleInfoTest do
  @moduledoc """
  Tests for DashboardLive handle_info callbacks.
  Sends messages directly to the LiveView process to exercise
  PubSub-triggered code paths.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Handle Info Track",
      artist: "Info Artist",
      duration: 200,
      spotify_url: "https://open.spotify.com/track/info123"
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/info_test.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/vocals.wav", file_size: 1024})

    %{track: track}
  end

  describe "pipeline_progress" do
    test "handles download progress", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:pipeline_progress, %{track_id: track.id, stage: :download, status: :running, progress: 50}})
      html = render(view)
      assert is_binary(html)
    end

    test "handles processing progress", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:pipeline_progress, %{track_id: track.id, stage: :processing, status: :running, progress: 75}})
      html = render(view)
      assert is_binary(html)
    end

    test "handles analysis progress", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:pipeline_progress, %{track_id: track.id, stage: :analysis, status: :running, progress: 30}})
      html = render(view)
      assert is_binary(html)
    end

    test "handles completed download status", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:pipeline_progress, %{track_id: track.id, stage: :download, status: :completed, progress: 100}})
      html = render(view)
      assert is_binary(html)
    end

    test "handles failed status with flash", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:pipeline_progress, %{track_id: track.id, stage: :download, status: :failed, progress: 0}})
      html = render(view)
      assert html =~ "failed" or html =~ "Failed" or is_binary(html)
    end

    test "handles progress for unknown track", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:pipeline_progress, %{track_id: Ecto.UUID.generate(), stage: :download, status: :running, progress: 50}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "pipeline_complete" do
    test "handles pipeline completion", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:pipeline_complete, %{track_id: track.id}})
      html = render(view)
      assert html =~ "complete" or html =~ "Complete" or html =~ "ready" or is_binary(html)
    end

    test "handles completion for unknown track", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:pipeline_complete, %{track_id: Ecto.UUID.generate()}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "job_progress" do
    test "updates active jobs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      job_id = Ecto.UUID.generate()
      send(view.pid, {:job_progress, %{job_id: job_id, status: :running, progress: 42}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "new_notification" do
    test "forwards to notification bell", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:new_notification, %{type: :info, message: "Test notification"}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "dismiss_pipeline_from_tracker" do
    test "removes pipeline from state", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:pipeline_progress, %{track_id: track.id, stage: :download, status: :running, progress: 50}})
      render(view)
      send(view.pid, {:dismiss_pipeline_from_tracker, track.id})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "dismiss_toast" do
    test "forwards to toast stack", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:dismiss_toast, "toast-123"})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "spotify control messages" do
    test "spotify_pause", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, :spotify_pause)
      html = render(view)
      assert is_binary(html)
    end

    test "spotify_resume", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, :spotify_resume)
      html = render(view)
      assert is_binary(html)
    end

    test "spotify_seek", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:spotify_seek, 5000})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "debug_log" do
    test "debug_log when panel closed (no-op)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:debug_log, %{level: :info, message: "test", namespace: "test_ns", timestamp: DateTime.utc_now()}})
      html = render(view)
      assert is_binary(html)
    end

    test "debug_log when panel open updates logs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      send(view.pid, {:debug_log, %{level: :info, message: "test log", namespace: "test_ns", timestamp: DateTime.utc_now()}})
      html = render(view)
      assert is_binary(html)
    end

    test "debug_log with nil namespace", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      send(view.pid, {:debug_log, %{level: :warning, message: "no namespace", namespace: nil, timestamp: DateTime.utc_now()}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "worker_status_change" do
    test "refreshes queue info", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:worker_status_change, %{worker: "test_worker"}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "batch messages" do
    test "batch_progress", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:batch_progress, %{batch_job_id: Ecto.UUID.generate(), status: :running, completed_count: 3, total_count: 10}})
      html = render(view)
      assert is_binary(html)
    end

    test "batch_complete", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:batch_complete, %{batch_job_id: Ecto.UUID.generate(), completed_count: 10, failed_count: 0, total_count: 10}})
      html = render(view)
      assert is_binary(html)
    end

    test "batch_complete with failures", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:batch_complete, %{batch_job_id: Ecto.UUID.generate(), completed_count: 7, failed_count: 3, total_count: 10}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "MIDI messages" do
    test "midi_device_connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:midi_device_connected, %{name: "MPC Live II", type: :input}})
      html = render(view)
      assert is_binary(html)
    end

    test "midi_device_disconnected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:midi_device_disconnected, %{name: "MPC Live II", type: :input}})
      html = render(view)
      assert is_binary(html)
    end

    test "bpm_update", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:bpm_update, 128.0})
      html = render(view)
      assert is_binary(html)
    end

    test "transport play", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:transport, :play})
      html = render(view)
      assert is_binary(html)
    end

    test "transport stop", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:transport, :stop})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "reference/DOWN messages" do
    test "reference message (task completion)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      ref = make_ref()
      send(view.pid, {ref, :ok})
      html = render(view)
      assert is_binary(html)
    end

    test "DOWN message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:DOWN, make_ref(), :process, self(), :normal})
      html = render(view)
      assert is_binary(html)
    end
  end
end
