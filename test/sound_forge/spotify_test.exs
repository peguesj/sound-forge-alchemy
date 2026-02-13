defmodule SoundForge.SpotifyTest do
  use ExUnit.Case, async: true

  import Mox

  alias SoundForge.Spotify
  alias SoundForge.Spotify.URLParser
  alias SoundForge.Spotify.MockClient

  # Ensure mocks are verified after each test
  setup :verify_on_exit!

  describe "URLParser.parse/1" do
    test "parses valid track URL with https" do
      assert {:ok, %{type: "track", id: "abc123"}} =
               URLParser.parse("https://open.spotify.com/track/abc123")
    end

    test "parses valid track URL without https" do
      assert {:ok, %{type: "track", id: "xyz789"}} =
               URLParser.parse("open.spotify.com/track/xyz789")
    end

    test "parses valid album URL" do
      assert {:ok, %{type: "album", id: "album456"}} =
               URLParser.parse("https://open.spotify.com/album/album456")
    end

    test "parses valid playlist URL" do
      assert {:ok, %{type: "playlist", id: "playlist789"}} =
               URLParser.parse("https://open.spotify.com/playlist/playlist789")
    end

    test "parses URL with international locale" do
      assert {:ok, %{type: "track", id: "track123"}} =
               URLParser.parse("https://open.spotify.com/intl-de/track/track123")
    end

    test "parses URL without 'open' subdomain" do
      assert {:ok, %{type: "track", id: "track123"}} =
               URLParser.parse("https://spotify.com/track/track123")
    end

    test "returns error for invalid URL format" do
      assert {:error, :invalid_spotify_url} = URLParser.parse("https://example.com/track/123")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_spotify_url} = URLParser.parse("")
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_spotify_url} = URLParser.parse(nil)
      assert {:error, :invalid_spotify_url} = URLParser.parse(123)
    end

    test "returns error for Spotify URL with invalid type" do
      assert {:error, :invalid_spotify_url} =
               URLParser.parse("https://open.spotify.com/artist/abc123")
    end
  end

  describe "Spotify.fetch_metadata/1" do
    test "fetches track metadata successfully" do
      track_data = %{
        "id" => "track123",
        "name" => "Test Song",
        "artists" => [%{"name" => "Test Artist"}],
        "album" => %{"name" => "Test Album"}
      }

      expect(MockClient, :fetch_track, fn "track123" ->
        {:ok, track_data}
      end)

      assert {:ok, ^track_data} =
               Spotify.fetch_metadata("https://open.spotify.com/track/track123")
    end

    test "fetches album metadata successfully" do
      album_data = %{
        "id" => "album456",
        "name" => "Test Album",
        "artists" => [%{"name" => "Test Artist"}],
        "tracks" => %{"items" => []}
      }

      expect(MockClient, :fetch_album, fn "album456" ->
        {:ok, album_data}
      end)

      assert {:ok, ^album_data} =
               Spotify.fetch_metadata("https://open.spotify.com/album/album456")
    end

    test "fetches playlist metadata successfully" do
      playlist_data = %{
        "id" => "playlist789",
        "name" => "Test Playlist",
        "owner" => %{"display_name" => "Test User"},
        "tracks" => %{"items" => []}
      }

      expect(MockClient, :fetch_playlist, fn "playlist789" ->
        {:ok, playlist_data}
      end)

      assert {:ok, ^playlist_data} =
               Spotify.fetch_metadata("https://open.spotify.com/playlist/playlist789")
    end

    test "returns error for invalid URL" do
      assert {:error, :invalid_spotify_url} = Spotify.fetch_metadata("invalid-url")
    end

    test "returns error when client returns error" do
      expect(MockClient, :fetch_track, fn "track123" ->
        {:error, :api_error}
      end)

      assert {:error, :api_error} =
               Spotify.fetch_metadata("https://open.spotify.com/track/track123")
    end

    test "handles API error responses" do
      expect(MockClient, :fetch_track, fn "track123" ->
        {:error, {:api_error, 404, %{"error" => %{"message" => "Not found"}}}}
      end)

      assert {:error, {:api_error, 404, %{"error" => %{"message" => "Not found"}}}} =
               Spotify.fetch_metadata("https://open.spotify.com/track/track123")
    end

    test "handles authentication errors" do
      expect(MockClient, :fetch_album, fn "album456" ->
        {:error, {:api_error, 401, %{"error" => %{"message" => "Unauthorized"}}}}
      end)

      assert {:error, {:api_error, 401, %{"error" => %{"message" => "Unauthorized"}}}} =
               Spotify.fetch_metadata("https://open.spotify.com/album/album456")
    end

    test "handles network errors" do
      expect(MockClient, :fetch_playlist, fn "playlist789" ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} =
               Spotify.fetch_metadata("https://open.spotify.com/playlist/playlist789")
    end
  end

  describe "edge cases" do
    test "handles very long Spotify IDs" do
      long_id = String.duplicate("a", 50)

      expect(MockClient, :fetch_track, fn ^long_id ->
        {:ok, %{"id" => long_id}}
      end)

      assert {:ok, %{"id" => ^long_id}} =
               Spotify.fetch_metadata("https://open.spotify.com/track/#{long_id}")
    end

    test "handles URLs with query parameters" do
      # URL parser should extract just the ID, ignoring query params
      url = "https://open.spotify.com/track/track123?si=abc&nd=1"

      expect(MockClient, :fetch_track, fn "track123" ->
        {:ok, %{"id" => "track123"}}
      end)

      assert {:ok, %{"id" => "track123"}} = Spotify.fetch_metadata(url)
    end
  end
end
