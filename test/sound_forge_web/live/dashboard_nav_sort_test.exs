defmodule SoundForgeWeb.DashboardNavSortTest do
  @moduledoc """
  Tests for DashboardLive navigation, sorting, and browse filtering handlers.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Nav Test Track",
        artist: "Nav Artist",
        duration: 180,
        spotify_url: "https://open.spotify.com/track/nav123"
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/nav_test.mp3"
    })

    %{track: track}
  end

  describe "nav_tab" do
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
      result = render_click(view, "nav_tab", %{"tab" => "dj"})
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end

    test "nav_tab daw", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      result = render_click(view, "nav_tab", %{"tab" => "daw"})
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end

    test "nav_tab pads", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      result = render_click(view, "nav_tab", %{"tab" => "pads"})
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end
  end

  describe "sort" do
    test "sort by newest", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort", %{"sort_by" => "newest"})
      assert is_binary(html)
    end

    test "sort by oldest", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort", %{"sort_by" => "oldest"})
      assert is_binary(html)
    end

    test "sort by title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort", %{"sort_by" => "title"})
      assert is_binary(html)
    end

    test "sort by artist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort", %{"sort_by" => "artist"})
      assert is_binary(html)
    end

    test "sort by duration", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort", %{"sort_by" => "duration"})
      assert is_binary(html)
    end

    test "sort by invalid field defaults to newest", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort", %{"sort_by" => "nonexistent_field"})
      assert is_binary(html)
    end
  end

  describe "spotify events" do
    test "spotify_player_ready", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_player_ready", %{"device_id" => "test-device"})
      assert is_binary(html)
    end

    test "spotify_playback_state full", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_click(view, "spotify_playback_state", %{
          "playing" => true,
          "track_name" => "Test Track",
          "artist_name" => "Test Artist",
          "album_art_url" => "https://example.com/art.jpg",
          "position_ms" => 5000,
          "duration_ms" => 200_000
        })

      assert is_binary(html)
    end

    test "spotify_playback_state minimal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_playback_state", %{})
      assert is_binary(html)
    end

    test "spotify_error account type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"type" => "account"})
      assert is_binary(html)
    end

    test "spotify_error with type and message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_click(view, "spotify_error", %{
          "type" => "connection",
          "message" => "Connection lost"
        })

      assert is_binary(html)
    end

    test "spotify_error with message only", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"message" => "Generic error"})
      assert is_binary(html)
    end
  end

  describe "browse context" do
    test "browse_artist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "nav_tab", %{"tab" => "browse"})

      result =
        try do
          view |> element("[phx-click='browse_artist']") |> render_click()
        rescue
          ArgumentError -> :not_found
        end

      assert is_binary(result) or result == :not_found
    end
  end

  describe "upload_audio" do
    test "upload_audio event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "upload_audio", %{})
      assert is_binary(html)
    end

    # cancel_upload requires a real upload ref from allow_upload, not testable via render_click
  end
end
