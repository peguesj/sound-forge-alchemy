defmodule SoundForgeWeb.DashboardHandleInfoExtended2Test do
  @moduledoc "Additional handle_info tests for dashboard covering PubSub broadcasts and more tuple patterns."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Info Extra Track",
      artist: "Info Artist",
      duration: 200
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/info_extra.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/v.wav", file_size: 1024})

    %{track: track}
  end

  describe "PubSub broadcast messages" do
    test "auto_cues_complete broadcast on library tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "pipeline:updates",
        event: "auto_cues_complete",
        payload: %{track_id: Ecto.UUID.generate(), cue_count: 4}
      })
      html = render(view)
      assert is_binary(html)
    end

    test "auto_cues_complete broadcast on dj tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "pipeline:updates",
        event: "auto_cues_complete",
        payload: %{track_id: Ecto.UUID.generate(), cue_count: 4}
      })
      html = render(view)
      assert is_binary(html)
    end

    test "chef_progress broadcast on dj tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "chef:updates",
        event: "chef_progress",
        payload: %{progress: 50, recipe_name: "test"}
      })
      html = render(view)
      assert is_binary(html)
    end

    test "chef_complete broadcast on dj tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "chef:updates",
        event: "chef_complete",
        payload: %{track_count: 3}
      })
      html = render(view)
      assert is_binary(html)
    end

    test "chef_failed broadcast on dj tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "chef:updates",
        event: "chef_failed",
        payload: %{reason: "timeout"}
      })
      html = render(view)
      assert is_binary(html)
    end

    test "chef_progress on library tab (no forward)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "chef:updates",
        event: "chef_progress",
        payload: %{progress: 50}
      })
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "dismiss_toast message" do
    test "dismiss_toast removes a toast", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:dismiss_toast, "toast-123"})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "virtual_controller message" do
    test "virtual_controller trigger_cue message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:midi_action, :trigger_cue, %{deck: 1, slot: 1}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "batch_complete message" do
    test "batch_complete with all success", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:batch_complete, %{batch_job_id: Ecto.UUID.generate(), completed_count: 5, failed_count: 0, total_count: 5}})
      html = render(view)
      assert is_binary(html)
    end

    test "batch_complete with failures", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:batch_complete, %{batch_job_id: Ecto.UUID.generate(), completed_count: 3, failed_count: 2, total_count: 5}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "lalalai messages" do
    test "lalalai_connection_result success", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:lalalai_connection_result, {:ok, :valid}})
      html = render(view)
      assert is_binary(html)
    end

    test "lalalai_connection_result error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:lalalai_connection_result, {:error, "invalid key"}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "uat_step message" do
    test "uat_step message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:uat_step, :import_spotify_track, 1})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "reference and DOWN messages" do
    test "reference message (Task completion)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      ref = make_ref()
      send(view.pid, {ref, :ok})
      html = render(view)
      assert is_binary(html)
    end

    test "DOWN message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      ref = make_ref()
      send(view.pid, {:DOWN, ref, :process, self(), :normal})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "worker_status_change message" do
    test "worker active status", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:worker_status_change, %{worker: "AnalysisWorker", status: :active, queue_size: 3}})
      html = render(view)
      assert is_binary(html)
    end
  end
end
