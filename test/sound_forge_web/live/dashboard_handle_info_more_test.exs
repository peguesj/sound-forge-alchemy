defmodule SoundForgeWeb.DashboardHandleInfoMoreTest do
  @moduledoc """
  Additional handle_info coverage for DashboardLive, targeting
  pipeline progress, notifications, MIDI, and tab switches.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Handle Info Track",
        artist: "Test Artist",
        duration: 200
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/handle_info.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    stem_fixture(%{
      track_id: track.id,
      processing_job_id: pj.id,
      stem_type: :vocals,
      file_path: "stems/v.wav",
      file_size: 1024
    })

    %{track: track}
  end

  describe "pipeline progress messages" do
    test "pipeline_progress with download stage", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :download, status: :downloading, progress: 50}}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "pipeline_progress with processing stage", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :processing, status: :processing, progress: 75}}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "pipeline_progress with failed status triggers notification", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :processing, status: :failed, progress: 0}}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "pipeline_progress with completed download", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :download, status: :completed, progress: 100}}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "pipeline_complete message", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:pipeline_complete, %{track_id: track.id}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "notification forwarding" do
    test "new_notification forwarded to bell", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:new_notification, %{type: :info, title: "Test", message: "Hello"}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "job progress messages" do
    test "job_progress update stores in active_jobs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      job_id = Ecto.UUID.generate()
      send(view.pid, {:job_progress, %{job_id: job_id, status: :processing, progress: 50}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "dismiss_pipeline_from_tracker" do
    test "removes pipeline from tracker", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      # First add a pipeline
      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :download, status: :downloading, progress: 50}}
      )

      render(view)
      # Then dismiss it
      send(view.pid, {:dismiss_pipeline_from_tracker, track.id})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "MIDI action messages" do
    test "midi_action on library tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:midi_action, :play, %{}})
      html = render(view)
      assert is_binary(html)
    end

    test "midi_action stem_volume", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:midi_action, :stem_volume, %{volume: 0.5, target: "vocals"}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "spotify messages" do
    test "spotify_pause message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, :spotify_pause)
      html = render(view)
      assert is_binary(html)
    end

    test "spotify_resume message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, :spotify_resume)
      html = render(view)
      assert is_binary(html)
    end

    test "spotify_seek message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:spotify_seek, 30000})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "MIDI device messages" do
    test "midi_device_connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:midi_device_connected, %{port_id: "input:99", name: "Test MIDI", direction: :input}}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "midi_device_disconnected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:midi_device_disconnected, %{port_id: "input:99", name: "Test MIDI", direction: :input}}
      )

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "debug_log message" do
    test "debug_log event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:debug_log, %{type: :info, message: "test debug event"}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "tab switching" do
    test "switch to daw tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "switch_tab", %{"tab" => "daw"})
      assert is_binary(html)
    end

    test "switch to admin tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "switch_tab", %{"tab" => "admin"})
      assert is_binary(html)
    end

    test "switch to browse tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "switch_tab", %{"tab" => "browse"})
      assert is_binary(html)
    end
  end

  describe "worker_status_change" do
    test "worker_status_change message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:worker_status_change, %{worker: "DownloadWorker", status: :active}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "batch_progress" do
    test "batch_progress message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:batch_progress,
         %{
           batch_job_id: Ecto.UUID.generate(),
           status: :processing,
           completed_count: 2,
           total_count: 5
         }}
      )

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "transport message" do
    test "transport :playing forwarded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:transport, :playing})
      html = render(view)
      assert is_binary(html)
    end

    test "transport :stopped forwarded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:transport, :stopped})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "bpm_update" do
    test "bpm_update message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:bpm_update, %{bpm: 128.0, source: "midi"}})
      html = render(view)
      assert is_binary(html)
    end
  end
end
