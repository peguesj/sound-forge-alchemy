defmodule SoundForge.Spotify.URLParserTest do
  use ExUnit.Case, async: true

  alias SoundForge.Spotify.URLParser

  describe "parse/1" do
    test "parses standard track URL" do
      assert {:ok, %{type: "track", id: "abc123"}} =
               URLParser.parse("https://open.spotify.com/track/abc123")
    end

    test "parses album URL" do
      assert {:ok, %{type: "album", id: "xyz789"}} =
               URLParser.parse("https://open.spotify.com/album/xyz789")
    end

    test "parses playlist URL" do
      assert {:ok, %{type: "playlist", id: "playlist123"}} =
               URLParser.parse("https://open.spotify.com/playlist/playlist123")
    end

    test "parses URL without https prefix" do
      assert {:ok, %{type: "track", id: "abc"}} =
               URLParser.parse("spotify.com/track/abc")
    end

    test "parses URL with intl prefix" do
      assert {:ok, %{type: "track", id: "abc"}} =
               URLParser.parse("https://open.spotify.com/intl-us/track/abc")
    end

    test "parses URL with query parameters" do
      assert {:ok, %{type: "track", id: "abc123"}} =
               URLParser.parse("https://open.spotify.com/track/abc123?si=foo")
    end

    test "returns error for invalid URL" do
      assert {:error, :invalid_spotify_url} = URLParser.parse("https://example.com/not-spotify")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_spotify_url} = URLParser.parse("")
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_spotify_url} = URLParser.parse(nil)
      assert {:error, :invalid_spotify_url} = URLParser.parse(123)
    end
  end
end
