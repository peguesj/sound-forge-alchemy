defmodule SoundForgeWeb.DashboardEventsBatch2Test do
  @moduledoc "Tests for remaining untested DashboardLive handle_event handlers."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "spotify events" do
    test "play_spotify event is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "play_spotify", %{"uri" => "spotify:track:abc123"})
      assert is_binary(html)
    end

    test "spotify_player_ready event is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_player_ready", %{})
      assert is_binary(html)
    end

    test "spotify_playback_state event is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_playback_state", %{"paused" => true, "position" => 0})
      assert is_binary(html)
    end

    test "spotify_error with account variant", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"account" => "premium_required"})
      assert is_binary(html)
    end

    test "spotify_error with type and message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_click(view, "spotify_error", %{"type" => "playback", "message" => "No device"})

      assert is_binary(html)
    end

    test "spotify_error with message only", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"message" => "Unknown error"})
      assert is_binary(html)
    end
  end

  describe "drawer events" do
    test "open_drawer event is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "open_drawer", %{})
      assert is_binary(html)
    end

    test "close_drawer event is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "close_drawer", %{})
      assert is_binary(html)
    end
  end

  describe "navigation events" do
    test "nav_all_tracks is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_all_tracks", %{})
      assert is_binary(html)
    end

    test "nav_recent is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_recent", %{})
      assert is_binary(html)
    end

    test "nav_playlist is handled", %{conn: conn, user: user} do
      playlist = playlist_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_playlist", %{"id" => playlist.id})
      assert is_binary(html)
    end

    test "nav_artists is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_artists", %{})
      assert is_binary(html)
    end

    test "nav_artist is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_artist", %{"name" => "Test Artist"})
      assert is_binary(html)
    end

    test "nav_albums is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_albums", %{})
      assert is_binary(html)
    end

    test "nav_album is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_album", %{"name" => "Test Album"})
      assert is_binary(html)
    end

    test "new_playlist is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "new_playlist", %{})
      assert is_binary(html)
    end
  end

  describe "lalalai modal extra events" do
    test "close_lalalai_modal is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "close_lalalai_modal", %{})
      assert is_binary(html)
    end

    test "test_lalalai_connection is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "test_lalalai_connection", %{})
      assert is_binary(html)
    end

    test "test_save_lalalai_key is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "test_save_lalalai_key", %{"key" => "test_key_123"})
      assert is_binary(html)
    end

    test "cancel_lalalai_task is handled", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :processing})
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "cancel_lalalai_task", %{"job-id" => pj.id})
      assert is_binary(html)
    end

    test "cancel_all_lalalai_tasks is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "cancel_all_lalalai_tasks", %{})
      assert is_binary(html)
    end

    test "select_voice_pack is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_voice_pack", %{"pack" => "deep"})
      assert is_binary(html)
    end
  end

  describe "batch process modal events" do
    test "start_batch_process is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "start_batch_process", %{})
      assert is_binary(html)
    end

    test "cancel_batch_modal is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "cancel_batch_modal", %{})
      assert is_binary(html)
    end

    test "confirm_batch_process is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "confirm_batch_process", %{})
      assert is_binary(html)
    end
  end

  describe "debug panel extra events" do
    test "close_debug_panel is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "close_debug_panel", %{})
      assert is_binary(html)
    end

    test "trace_select_job is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "trace_select_job", %{"job-id" => "123"})
      assert is_binary(html)
    end

    test "trace_refresh is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "trace_refresh", %{})
      assert is_binary(html)
    end

    test "debug_log_filter_ns is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_log_filter_ns", %{"namespace" => "oban"})
      assert is_binary(html)
    end

    test "filter_logs_by_worker is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "filter_logs_by_worker", %{"worker" => "DownloadWorker"})
      assert is_binary(html)
    end

    test "queue_load_more is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "queue_load_more", %{})
      assert is_binary(html)
    end

    test "anchor_job_logs is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "anchor_job_logs", %{"job-id" => "456"})
      assert is_binary(html)
    end

    test "devtools_reset_pipeline is handled", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "devtools_reset_pipeline", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end

  describe "UAT events" do
    test "uat_reset_scenario is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "uat_reset_scenario", %{})
      assert is_binary(html)
    end

    test "uat_clear_log is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "uat_clear_log", %{})
      assert is_binary(html)
    end
  end

  describe "keydown events" do
    test "generic keydown is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "keydown", %{"key" => "a"})
      assert is_binary(html)
    end
  end

  describe "load_in_pads event" do
    test "load_in_pads is handled", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "load_in_pads", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end

  # cancel_upload requires a real upload ref from allow_upload - skip
end
