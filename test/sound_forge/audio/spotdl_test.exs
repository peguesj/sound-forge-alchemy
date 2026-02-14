defmodule SoundForge.Audio.SpotDLTest do
  use ExUnit.Case, async: true

  alias SoundForge.Audio.SpotDL

  # These tests use the mock_spotify_dl.py script configured in config/test.exs

  describe "fetch_metadata/1" do
    test "returns track metadata for valid Spotify URL" do
      assert {:ok, [track | _]} =
               SpotDL.fetch_metadata("https://open.spotify.com/track/abc123")

      assert track["name"] == "Test Song"
      assert track["artists"] == ["Test Artist"]
      assert track["album_name"] == "Test Album"
      assert track["song_id"] == "abc123"
      assert track["duration"] == 180
      assert track["cover_url"] == "https://example.com/art.jpg"
    end

    test "returns error for invalid URL" do
      assert {:error, _reason} = SpotDL.fetch_metadata("not-a-spotify-url")
    end

    test "returns error for URL containing invalid" do
      assert {:error, _reason} =
               SpotDL.fetch_metadata("https://open.spotify.com/track/invalid")
    end

    test "returns per-track cover art for playlist URLs (not playlist mosaic)" do
      assert {:ok, tracks, _playlist} =
               SpotDL.fetch_metadata("https://open.spotify.com/playlist/pl_test123")

      assert length(tracks) == 2

      [track1, track2] = tracks
      assert track1["name"] == "Playlist Track 1"
      assert track2["name"] == "Playlist Track 2"

      # Each track should have its own album art, NOT the playlist mosaic cover
      assert track1["cover_url"] == "https://example.com/album-art-1.jpg"
      assert track2["cover_url"] == "https://example.com/album-art-2.jpg"

      # Verify they are distinct from what would be the playlist cover
      refute track1["cover_url"] == "https://example.com/playlist-mosaic.jpg"
      refute track2["cover_url"] == "https://example.com/playlist-mosaic.jpg"
    end
  end

  describe "download/2" do
    test "downloads track to specified directory" do
      tmp_dir = Path.join(System.tmp_dir!(), "sfa_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      assert {:ok, %{path: path, size: size}} =
               SpotDL.download("https://open.spotify.com/track/test123",
                 output_dir: tmp_dir,
                 output_template: "test_track"
               )

      assert File.exists?(path)
      assert size > 0
    end

    test "returns error for failed download" do
      tmp_dir = Path.join(System.tmp_dir!(), "sfa_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      assert {:error, _reason} =
               SpotDL.download("https://open.spotify.com/track/fail",
                 output_dir: tmp_dir
               )
    end
  end

  describe "available?/0" do
    test "returns true when python and mock script are available" do
      assert SpotDL.available?()
    end
  end
end
