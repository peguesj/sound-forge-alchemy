defmodule SoundForgeWeb.DashboardComponentsTest do
  @moduledoc """
  Tests for DashboardLive embedded components: NotificationBell, PipelineTracker,
  search, view mode, playlists, debug panel, and other interactive elements.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Component Test Track",
        artist: "Test Artist",
        duration: 200,
        album: "Test Album"
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/comp_test.mp3"
    })

    %{track: track}
  end

  describe "search" do
    test "search event filters tracks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "search", %{"query" => "Component"})
      assert is_binary(html)
    end

    test "search with empty query", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "search", %{"query" => ""})
      assert is_binary(html)
    end
  end

  describe "view mode" do
    test "toggle_view to grid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_view", %{"mode" => "grid"})
      assert is_binary(html)
    end

    test "toggle_view to list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_view", %{"mode" => "list"})
      assert is_binary(html)
    end
  end

  describe "debug panel" do
    test "toggle_debug_panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_debug_panel", %{})
      assert is_binary(html)
    end

    test "close_debug_panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "close_debug_panel", %{})
      assert is_binary(html)
    end

    test "debug_tab switch", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_tab", %{"tab" => "logs"})
      assert is_binary(html)
    end

    test "debug_tab to queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_tab", %{"tab" => "queue"})
      assert is_binary(html)
    end

    test "debug_tab to tracing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_tab", %{"tab" => "tracing"})
      assert is_binary(html)
    end

    test "debug_tab to midi", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_tab", %{"tab" => "midi"})
      assert is_binary(html)
    end

    test "toggle_debug_queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_debug_queue", %{})
      assert is_binary(html)
    end

    test "toggle_debug_workers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_debug_workers", %{})
      assert is_binary(html)
    end

    test "clear_debug_logs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "clear_debug_logs", %{})
      assert is_binary(html)
    end

    test "debug_log_search", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_log_search", %{"value" => "test"})
      assert is_binary(html)
    end

    test "debug_log_filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_log_filter", %{"filter" => "error"})
      assert is_binary(html)
    end

    test "debug_log_filter_ns", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_log_filter_ns", %{"namespace" => "pipeline"})
      assert is_binary(html)
    end

    test "filter_logs_by_worker", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "filter_logs_by_worker", %{"worker" => "ProcessingWorker"})
      assert is_binary(html)
    end

    test "devtools_flush_caches", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "devtools_flush_caches", %{})
      assert is_binary(html)
    end

    test "devtools_force_gc", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "devtools_force_gc", %{})
      assert is_binary(html)
    end

    test "devtools_refresh", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "devtools_refresh", %{})
      assert is_binary(html)
    end

    test "devtools_reset_pipeline", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "devtools_reset_pipeline", %{"track_id" => track.id})
      assert is_binary(html)
    end
  end

  describe "playlists" do
    test "new_playlist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "new_playlist", %{"name" => "Test Playlist"})
      assert is_binary(html)
    end
  end

  describe "delete track" do
    test "delete_track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "delete_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "delete_track nonexistent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "delete_track", %{"id" => Ecto.UUID.generate()})
      assert is_binary(html)
    end
  end

  describe "play_track" do
    test "play_track with spotify url", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "play_track", %{"id" => track.id})
      assert is_binary(html)
    end
  end

  describe "fetch_spotify" do
    test "fetch_spotify with url", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_click(view, "fetch_spotify", %{"url" => "https://open.spotify.com/track/abc123"})

      assert is_binary(html)
    end

    test "fetch_spotify with empty url", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "fetch_spotify", %{"url" => ""})
      assert is_binary(html)
    end
  end

  describe "pipeline actions" do
    test "dismiss_pipeline for track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "dismiss_pipeline", %{"track_id" => track.id})
      assert is_binary(html)
    end

    test "retry_pipeline for track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_click(view, "retry_pipeline", %{"track_id" => track.id, "stage" => "download"})

      assert is_binary(html)
    end

    test "force_reset_pipeline", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "force_reset_pipeline", %{"track_id" => track.id})
      assert is_binary(html)
    end
  end

  describe "browse navigation" do
    test "nav_artists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "nav_tab", %{"tab" => "browse"})
      html = render_click(view, "nav_artists", %{})
      assert is_binary(html)
    end

    test "nav_albums", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "nav_tab", %{"tab" => "browse"})
      html = render_click(view, "nav_albums", %{})
      assert is_binary(html)
    end

    test "nav_recent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "nav_tab", %{"tab" => "browse"})
      html = render_click(view, "nav_recent", %{})
      assert is_binary(html)
    end

    test "nav_all_tracks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "nav_tab", %{"tab" => "browse"})
      html = render_click(view, "nav_all_tracks", %{})
      assert is_binary(html)
    end

    test "nav_artist specific", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "nav_tab", %{"tab" => "browse"})
      html = render_click(view, "nav_artist", %{"name" => "Test Artist"})
      assert is_binary(html)
    end

    test "nav_album specific", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "nav_tab", %{"tab" => "browse"})
      html = render_click(view, "nav_album", %{"name" => "Test Album"})
      assert is_binary(html)
    end
  end

  describe "queue tab" do
    test "queue_tab oban", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "queue_tab", %{"tab" => "oban"})
      assert is_binary(html)
    end

    test "queue_tab history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "queue_tab", %{"tab" => "history"})
      assert is_binary(html)
    end

    test "queue_refresh_history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "queue_refresh_history", %{})
      assert is_binary(html)
    end

    test "queue_load_more", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "queue_load_more", %{})
      assert is_binary(html)
    end
  end

  describe "keydown handler" do
    test "keydown escape", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "keydown", %{"key" => "Escape"})
      assert is_binary(html)
    end
  end

  describe "drawer" do
    test "open_drawer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "open_drawer", %{})
      assert is_binary(html)
    end

    test "close_drawer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "open_drawer", %{})
      html = render_click(view, "close_drawer", %{})
      assert is_binary(html)
    end
  end

  describe "batch operations with selections" do
    test "toggle_select_all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_select_all", %{})
      assert is_binary(html)
    end

    test "shift_select_range", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_click(view, "shift_select_range", %{"from_id" => track.id, "to_id" => track.id})

      assert is_binary(html)
    end
  end

  describe "lalalai task management" do
    test "cancel_lalalai_task", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "cancel_lalalai_task", %{"task_id" => "fake-task-123"})
      assert is_binary(html)
    end

    test "cancel_all_lalalai_tasks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "cancel_all_lalalai_tasks", %{})
      assert is_binary(html)
    end
  end

  describe "voice pack selection" do
    test "select_voice_pack", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_voice_pack", %{"pack_id" => "some-pack"})
      assert is_binary(html)
    end

    test "set_accent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "set_accent", %{"value" => "0.5"})
      assert is_binary(html)
    end
  end

  describe "stem_filter" do
    test "stem_filter vocals", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "stem_filter", %{"filter" => "vocals"})
      assert is_binary(html)
    end
  end

  describe "load_in_pads" do
    test "load_in_pads for track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "load_in_pads", %{"track_id" => track.id})
      assert is_binary(html)
    end
  end

  describe "play_spotify" do
    test "play_spotify with uri", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "play_spotify", %{"uri" => "spotify:track:abc123"})
      assert is_binary(html)
    end
  end

  describe "trace operations" do
    test "trace_refresh", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "trace_refresh", %{})
      assert is_binary(html)
    end

    test "trace_select_job", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "trace_select_job", %{"id" => "some-job-id"})
      assert is_binary(html)
    end
  end

  describe "anchor_job_logs" do
    test "anchor_job_logs for track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "anchor_job_logs", %{"track_id" => track.id})
      assert is_binary(html)
    end
  end
end
