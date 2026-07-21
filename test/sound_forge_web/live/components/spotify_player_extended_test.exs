defmodule SoundForgeWeb.Live.Components.SpotifyPlayerExtendedTest do
  @moduledoc "Extended tests for SpotifyPlayer rendering states."
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.SpotifyPlayer

  describe "render with playback data" do
    test "renders playing state with track info" do
      html =
        render_component(SpotifyPlayer, %{
          id: "sp-playing",
          spotify_linked: true,
          spotify_premium: true,
          spotify_playback: %{
            playing: true,
            track_name: "Test Song",
            artist_name: "Test Artist",
            album_art_url: "https://example.com/art.jpg",
            position_ms: 60_000,
            duration_ms: 240_000
          }
        })

      assert html =~ "Test Song"
      assert html =~ "Test Artist"
      assert is_binary(html)
    end

    test "renders paused state" do
      html =
        render_component(SpotifyPlayer, %{
          id: "sp-paused",
          spotify_linked: true,
          spotify_premium: true,
          spotify_playback: %{
            playing: false,
            track_name: "Paused Track",
            artist_name: "Paused Artist",
            album_art_url: nil,
            position_ms: 30_000,
            duration_ms: 180_000
          }
        })

      assert html =~ "Paused Track"
      assert is_binary(html)
    end

    test "renders not linked state" do
      html =
        render_component(SpotifyPlayer, %{
          id: "sp-unlinked",
          spotify_linked: false,
          spotify_premium: false,
          spotify_playback: nil
        })

      assert is_binary(html)
    end

    test "renders linked but no playback" do
      html =
        render_component(SpotifyPlayer, %{
          id: "sp-idle",
          spotify_linked: true,
          spotify_premium: true,
          spotify_playback: nil
        })

      assert is_binary(html)
    end

    test "renders non-premium user" do
      html =
        render_component(SpotifyPlayer, %{
          id: "sp-free",
          spotify_linked: true,
          spotify_premium: false,
          spotify_playback: nil
        })

      assert is_binary(html)
    end

    test "renders with zero duration" do
      html =
        render_component(SpotifyPlayer, %{
          id: "sp-zero",
          spotify_linked: true,
          spotify_premium: true,
          spotify_playback: %{
            playing: true,
            track_name: "Zero Duration",
            artist_name: "Artist",
            album_art_url: nil,
            position_ms: 0,
            duration_ms: 0
          }
        })

      assert is_binary(html)
    end

    test "renders at end of track" do
      html =
        render_component(SpotifyPlayer, %{
          id: "sp-end",
          spotify_linked: true,
          spotify_premium: true,
          spotify_playback: %{
            playing: false,
            track_name: "Finished Track",
            artist_name: "Done Artist",
            album_art_url: "https://example.com/done.jpg",
            position_ms: 240_000,
            duration_ms: 240_000
          }
        })

      assert html =~ "Finished Track"
      assert is_binary(html)
    end
  end
end
