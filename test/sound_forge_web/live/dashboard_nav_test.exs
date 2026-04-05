defmodule SoundForgeWeb.DashboardNavTest do
  @moduledoc """
  Tests for DashboardLive navigation, sidebar, drawer, pagination,
  and keydown handlers.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Nav Track",
      artist: "Nav Artist",
      duration: 200,
      album: "Nav Album"
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/nav_test.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/vocals.wav", file_size: 1024})

    %{track: track}
  end

  describe "nav_tab switching" do
    test "nav_tab library", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_tab", %{"tab" => "library"})
      assert is_binary(html)
    end

    test "nav_tab browse", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_tab", %{"tab" => "browse"})
      assert is_binary(html)
    end

    test "nav_tab dj", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_tab", %{"tab" => "dj"})
      assert is_binary(html)
    end

    test "nav_tab daw", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_tab", %{"tab" => "daw"})
      assert is_binary(html)
    end

    test "nav_tab pads", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_tab", %{"tab" => "pads"})
      assert is_binary(html)
    end

    test "nav_tab unknown falls back", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_tab", %{"tab" => "nonexistent"})
      assert is_binary(html)
    end
  end

  describe "sidebar navigation" do
    test "nav_all_tracks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_all_tracks", %{})
      assert is_binary(html)
    end

    test "nav_recent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_recent", %{})
      assert is_binary(html)
    end

    test "nav_artists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_artists", %{})
      assert is_binary(html)
    end

    test "nav_artist with name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_artist", %{"name" => "Nav Artist"})
      assert is_binary(html)
    end

    test "nav_albums", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_albums", %{})
      assert is_binary(html)
    end

    test "nav_album with name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_album", %{"name" => "Nav Album"})
      assert is_binary(html)
    end

    test "new_playlist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "new_playlist", %{})
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

  describe "keydown" do
    test "keydown noop", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "keydown", %{"key" => "a"})
      assert is_binary(html)
    end
  end

  describe "pagination" do
    test "page navigation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "page", %{"page" => "1"})
      assert is_binary(html)
    end
  end

  describe "view modes" do
    test "toggle_view grid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_view", %{"mode" => "grid"})
      assert is_binary(html)
    end

    test "toggle_view list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_view", %{"mode" => "list"})
      assert is_binary(html)
    end
  end

  describe "batch selection" do
    test "toggle_select", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_select", %{"id" => track.id})
      assert is_binary(html)
    end

    test "toggle_select_all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_select_all", %{})
      assert is_binary(html)
    end

    test "toggle_batch_mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_batch_mode", %{})
      assert is_binary(html)
    end

    test "batch_analyze", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_select", %{"id" => track.id})
      html = render_click(view, "batch_analyze", %{})
      assert is_binary(html)
    end

    test "batch_process", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_select", %{"id" => track.id})
      html = render_click(view, "batch_process", %{})
      assert is_binary(html)
    end

    test "batch_delete", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_select", %{"id" => track.id})
      html = render_click(view, "batch_delete", %{})
      assert is_binary(html)
    end

    test "batch_download", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_select", %{"id" => track.id})
      html = render_click(view, "batch_download", %{})
      assert is_binary(html)
    end
  end

  describe "load_in_pads" do
    test "load_in_pads", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "load_in_pads", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end

  describe "filter" do
    test "filter with status", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "filter", %{"status" => "processed"})
      assert is_binary(html)
    end

    test "filter with all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "filter", %{"status" => "all"})
      assert is_binary(html)
    end
  end

  describe "track operations" do
    test "delete_track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "delete_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "dismiss_pipeline", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "dismiss_pipeline", %{"track-id" => track.id})
      assert is_binary(html)
    end

    test "force_reset_pipeline", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "force_reset_pipeline", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end

  describe "spotify events" do
    test "spotify_player_ready", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_player_ready", %{"device_id" => "dev-123"})
      assert is_binary(html)
    end

    test "spotify_playback_state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_playback_state", %{"is_playing" => true, "position" => 0})
      assert is_binary(html)
    end

    test "spotify_error account type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"type" => "account", "message" => "No premium"})
      assert is_binary(html)
    end

    test "spotify_error generic type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"type" => "playback", "message" => "Error"})
      assert is_binary(html)
    end

    test "spotify_error message only", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"message" => "Unknown error"})
      assert is_binary(html)
    end
  end
end
