defmodule SoundForge.Audio.SpotDLTest do
  use ExUnit.Case, async: true

  alias SoundForge.Audio.SpotDL

  # These tests use the mock_spotdl.sh script configured in config/test.exs

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
    test "returns true when mock spotdl is configured" do
      assert SpotDL.available?()
    end
  end
end
