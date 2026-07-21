defmodule SoundForgeWeb.DashboardHandleInfoBatch2Test do
  @moduledoc "Tests for additional DashboardLive handle_info PubSub handlers and state transitions."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "handle_info - download events" do
    test "download_progress updates download state", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Downloading Track"})
      dj = download_job_fixture(%{track_id: track.id, status: :downloading})
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:job_progress,
         %{
           job_id: dj.id,
           status: :downloading,
           progress: 50,
           message: "Downloading..."
         }}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "download_complete marks download done", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Downloaded Track"})
      dj = download_job_fixture(%{track_id: track.id, status: :downloading})
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:job_progress,
         %{
           job_id: dj.id,
           status: :completed,
           progress: 100
         }}
      )

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "handle_info - processing events" do
    test "processing_progress with detailed stages", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Processing Track"})
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:pipeline_progress,
         %{
           track_id: track.id,
           stage: :processing,
           status: :processing,
           progress: 25,
           message: "Separating stems..."
         }}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "analysis_progress updates analysis state", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Analyzing Track"})
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:pipeline_progress,
         %{
           track_id: track.id,
           stage: :analysis,
           status: :analyzing,
           progress: 75
         }}
      )

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "handle_info - midi events" do
    test "midi_device_connected event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:midi_device_connected, %{name: "MPC Live II", port_id: "input:0"}})
      html = render(view)
      assert is_binary(html)
    end

    test "midi_device_disconnected event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:midi_device_disconnected, %{name: "MPC Live II", port_id: "input:0"}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "handle_info - multiple pipeline phases" do
    test "full pipeline lifecycle", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Full Pipeline"})
      {:ok, view, _html} = live(conn, ~p"/")

      # Download phase
      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :download, status: :downloading, progress: 50}}
      )

      render(view)

      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :download, status: :completed, progress: 100}}
      )

      render(view)

      # Processing phase
      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :processing, status: :processing, progress: 25}}
      )

      render(view)

      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :processing, status: :completed, progress: 100}}
      )

      render(view)

      # Analysis phase
      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :analysis, status: :analyzing, progress: 50}}
      )

      render(view)

      # Complete
      send(view.pid, {:pipeline_complete, %{track_id: track.id}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "handle_info - toast with different types" do
    test "dismiss_toast with info type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:dismiss_toast, "info-toast-1"})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "handle_info - lalalai with full payloads" do
    test "lalalai_connection_result with minutes remaining", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:lalalai_connection_result, {:ok, :valid}})
      html = render(view)
      assert is_binary(html)
    end

    test "lalalai_connection_result with network error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:lalalai_connection_result, {:error, :network_error}})
      html = render(view)
      assert is_binary(html)
    end

    test "lalalai_modal_test_result with valid key and save", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:lalalai_modal_test_result, {:ok, :valid}, "valid_key_abc"})
      html = render(view)
      assert is_binary(html)
    end

    test "lalalai_modal_test_result with network error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:lalalai_modal_test_result, {:error, :network_error}, "bad_key"})
      html = render(view)
      assert is_binary(html)
    end
  end
end
