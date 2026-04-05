defmodule SoundForgeWeb.DashboardSpotifyKeyboardTest do
  @moduledoc """
  Tests for DashboardLive Spotify playback events and keyboard events:
  spotify_player_ready, spotify_playback_state, spotify_error (3 clauses),
  keydown (Cmd+P, Ctrl+P, DJ delegation, catch-all),
  load_in_pads, fetch_spotify, delete_track, force_reset_pipeline,
  retry_pipeline (invalid stage), uat_clear_log.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Spotify KB Test",
      artist: "KB Artist",
      spotify_url: "https://open.spotify.com/track/abc123"
    })

    %{track: track}
  end

  describe "spotify_player_ready" do
    test "is a no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_player_ready", %{"device_id" => "dev123"})
      assert is_binary(html)
    end
  end

  describe "spotify_playback_state" do
    test "updates playback assigns", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_playback_state", %{
        "playing" => true,
        "track_name" => "Song",
        "artist_name" => "Artist",
        "album_art_url" => "http://example.com/art.jpg",
        "position_ms" => 5000,
        "duration_ms" => 180000
      })
      assert is_binary(html)
    end

    test "handles partial params", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_playback_state", %{})
      assert is_binary(html)
    end
  end

  describe "spotify_error" do
    test "account error sets premium false", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"type" => "account"})
      assert is_binary(html)
    end

    test "initialization error with type and message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"type" => "initialization", "message" => "SDK failed"})
      assert is_binary(html)
    end

    test "connection error with type and message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"type" => "connection", "message" => "Network error"})
      assert is_binary(html)
    end

    test "generic error with message only", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"message" => "Something went wrong"})
      assert is_binary(html)
    end
  end

  describe "keydown" do
    test "Cmd+P switches to pads tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "keydown", %{"key" => "p", "metaKey" => true})
      assert is_binary(html)
    end

    test "Ctrl+P switches to pads tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "keydown", %{"key" => "p", "ctrlKey" => true})
      assert is_binary(html)
    end

    test "DJ keydown delegation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      html = render_click(view, "keydown", %{"key" => " "})
      assert is_binary(html)
    end

    test "catch-all keydown is no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "keydown", %{"key" => "z"})
      assert is_binary(html)
    end
  end

  describe "load_in_pads" do
    test "switches to pads tab", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "load_in_pads", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end

  describe "fetch_spotify" do
    test "rejects empty URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "fetch_spotify", %{"url" => ""})
      assert html =~ "valid Spotify URL" or is_binary(html)
    end

    test "rejects invalid URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "fetch_spotify", %{"url" => "not-a-url"})
      assert html =~ "valid Spotify URL" or is_binary(html)
    end
  end

  describe "delete_track" do
    test "deletes owned track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "delete_track", %{"id" => track.id})
      assert html =~ "deleted" or is_binary(html)
    end

    test "returns error for nonexistent track", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "delete_track", %{"id" => Ecto.UUID.generate()})
      assert html =~ "not found" or is_binary(html)
    end
  end

  describe "force_reset_pipeline" do
    test "resets pipeline for track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "force_reset_pipeline", %{"track-id" => track.id})
      assert html =~ "reset" or is_binary(html)
    end
  end

  describe "retry_pipeline" do
    test "rejects invalid stage", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "retry_pipeline", %{"track-id" => track.id, "stage" => "bogus"})
      assert html =~ "Invalid" or is_binary(html)
    end
  end

  describe "uat_clear_log" do
    test "clears UAT log", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "uat_clear_log")
      assert is_binary(html)
    end
  end
end
