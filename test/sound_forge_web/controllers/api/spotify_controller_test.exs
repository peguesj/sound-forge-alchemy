defmodule SoundForgeWeb.API.SpotifyControllerTest do
  use SoundForgeWeb.ConnCase

  import Mox

  setup :register_and_auth_api_user
  setup :verify_on_exit!

  describe "POST /api/spotify/fetch" do
    test "returns metadata for valid Spotify URL", %{conn: conn} do
      expect(SoundForge.Spotify.MockClient, :fetch_track, fn "12345" ->
        {:ok,
         %{
           "id" => "12345",
           "name" => "Test Song",
           "artists" => [%{"name" => "Test Artist"}],
           "album" => %{"name" => "Test Album"},
           "duration_ms" => 180_000
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{url: "https://open.spotify.com/track/12345"})

      assert %{
               "success" => true,
               "metadata" => metadata
             } = json_response(conn, 200)

      assert is_map(metadata)
    end

    test "returns error when url parameter is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{})

      assert %{"error" => "url parameter is required"} = json_response(conn, 400)
    end

    test "returns error when url is empty string", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{url: ""})

      assert %{"error" => "url parameter is required"} = json_response(conn, 400)
    end

    test "returns error when url is not a string", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{url: 12_345})

      assert %{"error" => "url parameter is required"} = json_response(conn, 400)
    end

    test "returns error for invalid Spotify URL format", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{url: "https://example.com/not-spotify"})

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "returns metadata for album URL", %{conn: conn} do
      expect(SoundForge.Spotify.MockClient, :fetch_album, fn "album123" ->
        {:ok,
         %{
           "id" => "album123",
           "name" => "Test Album",
           "artists" => [%{"name" => "Test Artist"}],
           "tracks" => %{"items" => []}
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{url: "https://open.spotify.com/album/album123"})

      assert %{"success" => true, "metadata" => _} = json_response(conn, 200)
    end

    test "returns metadata for playlist URL", %{conn: conn} do
      expect(SoundForge.Spotify.MockClient, :fetch_playlist, fn "playlist456" ->
        {:ok,
         %{
           "id" => "playlist456",
           "name" => "Test Playlist",
           "tracks" => %{"items" => []}
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{url: "https://open.spotify.com/playlist/playlist456"})

      assert %{"success" => true, "metadata" => _} = json_response(conn, 200)
    end

    test "returns error when Spotify API fails", %{conn: conn} do
      expect(SoundForge.Spotify.MockClient, :fetch_track, fn "fail999" ->
        {:error, {:api_error, 404, %{"error" => %{"message" => "not found"}}}}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{url: "https://open.spotify.com/track/fail999"})

      assert %{"error" => _} = json_response(conn, 400)
    end
  end
end
