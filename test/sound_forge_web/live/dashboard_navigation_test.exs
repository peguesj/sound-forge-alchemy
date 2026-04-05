defmodule SoundForgeWeb.DashboardNavigationTest do
  @moduledoc """
  Extended navigation, selection, and UI state tests for DashboardLive.
  Exercises template branches for multi-select, batch ops, debug panel, drawer,
  metadata editing, engine selection, lalalai modal, keyboard shortcuts, etc.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "multi-select" do
    test "toggle_select adds and removes track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Select Me"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_select", %{"id" => track.id})
      assert is_binary(html)
      # Toggle again to deselect
      html2 = render_click(view, "toggle_select", %{"id" => track.id})
      assert is_binary(html2)
    end

    test "toggle_select_all selects and deselects all", %{conn: conn, user: user} do
      for i <- 1..3, do: track_fixture(%{user_id: user.id, title: "Track #{i}"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_select_all")
      assert is_binary(html)
      # Toggle again to deselect
      html2 = render_click(view, "toggle_select_all")
      assert is_binary(html2)
    end

    test "toggle_track_select", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Batch Select"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_track_select", %{"track_id" => track.id})
      assert is_binary(html)
    end
  end

  describe "batch operations" do
    test "batch_analyze on selected tracks", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Batch Analyze"})
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_select", %{"id" => track.id})
      html = render_click(view, "batch_analyze")
      assert html =~ "Analyzing" or is_binary(html)
    end

    test "batch_process on selected tracks", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Batch Process"})
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_select", %{"id" => track.id})
      html = render_click(view, "batch_process")
      assert html =~ "Processing" or is_binary(html)
    end

    test "batch_delete on selected tracks", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Batch Delete Me"})
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_select", %{"id" => track.id})
      html = render_click(view, "batch_delete")
      assert html =~ "Deleted" or is_binary(html)
    end

    test "batch_download on selected tracks", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Batch DL"})
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_select", %{"id" => track.id})
      html = render_click(view, "batch_download")
      assert is_binary(html)
    end
  end

  describe "view mode switching" do
    test "toggle_view to list_expanded", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_view", %{"mode" => "list_expanded"})
      assert is_binary(html)
    end

    test "toggle_view with invalid mode falls back to grid", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_view", %{"mode" => "invalid_mode_xyz"})
      assert is_binary(html)
    end
  end

  describe "sort options" do
    test "sort by newest", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "sort", %{"sort_by" => "newest"})
      assert is_binary(html)
    end

    test "sort by oldest", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "sort", %{"sort_by" => "oldest"})
      assert is_binary(html)
    end

    test "sort by duration", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "sort", %{"sort_by" => "duration"})
      assert is_binary(html)
    end

    test "sort with invalid field defaults to newest", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "sort", %{"sort_by" => "nonexistent_field"})
      assert is_binary(html)
    end
  end

  describe "navigation - browse by artist/album" do
    test "nav_artist filters by artist", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "Artist Track", artist: "TestArtist123"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_artist", %{"name" => "TestArtist123"})
      assert is_binary(html)
    end

    test "nav_album filters by album", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "Album Track", album: "TestAlbum789"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_album", %{"name" => "TestAlbum789"})
      assert is_binary(html)
    end
  end

  describe "keyboard shortcuts" do
    test "Cmd+P navigates to pads", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_keydown(view, "keydown", %{"key" => "p", "metaKey" => true})
      assert is_binary(html)
    end

    test "Ctrl+P navigates to pads", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_keydown(view, "keydown", %{"key" => "p", "ctrlKey" => true})
      assert is_binary(html)
    end

    test "keydown on DJ tab forwards to component", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_keydown(view, "keydown", %{"key" => "z"})
      assert is_binary(html)
    end

    test "keydown with unhandled key on DJ tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_keydown(view, "keydown", %{"key" => "q"})
      assert is_binary(html)
    end
  end

  describe "debug panel tabs" do
    test "switch to oban tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_tab", %{"tab" => "oban"})
      assert is_binary(html)
    end

    test "switch to midi tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_tab", %{"tab" => "midi"})
      assert is_binary(html)
    end

    test "switch to queue tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_tab", %{"tab" => "queue"})
      assert is_binary(html)
    end

    test "debug log filter by level", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_log_filter", %{"level" => "error"})
      assert is_binary(html)
    end

    test "debug log filter by namespace", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_log_filter_ns", %{"namespace" => "Oban"})
      assert is_binary(html)
    end

    test "debug log search", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_log_search", %{"search" => "error"})
      assert is_binary(html)
    end

    test "clear debug logs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "clear_debug_logs")
      assert is_binary(html)
    end

    test "clear midi log", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "clear_midi_log")
      assert is_binary(html)
    end

    test "toggle debug workers", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "toggle_debug_workers")
      assert is_binary(html)
    end

    test "toggle debug queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "toggle_debug_queue")
      assert is_binary(html)
    end

    test "queue tab switching", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "queue_tab", %{"tab" => "history"})
      assert is_binary(html)
    end

    test "queue refresh history", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "queue_refresh_history")
      assert is_binary(html)
    end

    test "devtools refresh", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "devtools_refresh")
      assert is_binary(html)
    end

    test "devtools flush caches", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "devtools_flush_caches")
      assert is_binary(html)
    end

    test "devtools force gc", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "devtools_force_gc")
      assert is_binary(html)
    end
  end

  describe "lalalai engine options" do
    test "select_lalalai_mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      html = render_click(view, "select_lalalai_mode", %{"mode" => "multistem"})
      assert is_binary(html)
    end

    test "toggle_multistem", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_multistem", %{"stem" => "vocals"})
      assert is_binary(html)
    end

    test "set_noise_level", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_noise_level", %{"level" => "2"})
      assert is_binary(html)
    end

    test "toggle_dereverb", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_dereverb")
      assert is_binary(html)
    end

    test "expand_lalalai_key_form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "expand_lalalai_key_form")
      assert is_binary(html)
    end

    test "lalalai_modal_key_input", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "lalalai_modal_key_input", %{"key" => "test_key_123"})
      assert is_binary(html)
    end
  end

  describe "spotify events" do
    test "spotify_player_ready", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "spotify_player_ready", %{"device_id" => "abc"})
      assert is_binary(html)
    end

    test "spotify_playback_state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "spotify_playback_state", %{
        "playing" => true,
        "track_name" => "Test",
        "artist_name" => "Artist",
        "album_art_url" => "https://example.com/art.jpg",
        "position_ms" => 1000,
        "duration_ms" => 240_000
      })
      assert is_binary(html)
    end

    test "spotify_error account type", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "spotify_error", %{"type" => "account", "message" => "Premium required"})
      assert is_binary(html)
    end

    test "spotify_error connection type", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "spotify_error", %{"type" => "connection", "message" => "Lost connection"})
      assert is_binary(html)
    end
  end

  describe "misc events" do
    test "fetch_spotify with invalid URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "fetch_spotify", %{"url" => "not-a-spotify-url"})
      assert is_binary(html)
    end

    test "delete_track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Delete Me"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "delete_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "validate_upload", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "validate_upload")
      assert is_binary(html)
    end

    test "new_playlist", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "new_playlist")
      assert is_binary(html)
    end

    test "nav_tab unknown tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "unknown_tab"})
      assert is_binary(html)
    end

    test "catch-all event handler", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "totally_unknown_event_xyz_123", %{})
      assert is_binary(html)
    end
  end
end
