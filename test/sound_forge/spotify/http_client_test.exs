defmodule SoundForge.Spotify.HTTPClientTest do
  @moduledoc """
  Tests for the concrete Spotify HTTP client implementation.

  All HTTP requests are intercepted by Req.Test plug (configured in config/test.exs)
  to prevent real Spotify API calls. This eliminates rate-limiting risks and ensures
  deterministic, fast test runs.

  ## Architecture

  The HTTPClient implements the `SoundForge.Spotify.Client` behaviour and uses Req
  for HTTP transport. In test mode, the `:spotify_req_options` config injects
  `plug: {Req.Test, SoundForge.Spotify.HTTPClient}`, routing all requests through
  `Req.Test.stub/2` handlers defined in each test.

  Higher-level tests (SpotifyTest, SpotifyControllerTest) use Mox on the behaviour
  boundary instead. This test file validates the concrete HTTP/ETS implementation.
  """

  use ExUnit.Case, async: false

  alias SoundForge.Spotify.HTTPClient

  @token_table :spotify_tokens

  setup do
    # Clean up ETS table before each test to ensure isolation
    try do
      :ets.delete(@token_table)
    rescue
      ArgumentError -> :ok
    end

    # Ensure valid test credentials are available (overridden per-test as needed)
    original = Application.get_env(:sound_forge, :spotify)

    on_exit(fn ->
      if original do
        Application.put_env(:sound_forge, :spotify, original)
      else
        Application.delete_env(:sound_forge, :spotify)
      end
    end)

    :ok
  end

  describe "init/0" do
    test "creates ETS table" do
      assert HTTPClient.init() == @token_table
    end

    test "returns :already_exists when table exists" do
      HTTPClient.init()
      assert HTTPClient.init() == :already_exists
    end
  end

  describe "credential validation (via fetch_track)" do
    test "returns error when client_id is missing" do
      Application.put_env(:sound_forge, :spotify, client_id: nil, client_secret: "secret")
      assert {:error, :missing_client_id} = HTTPClient.fetch_track("test123")
    end

    test "returns error when client_secret is missing" do
      Application.put_env(:sound_forge, :spotify, client_id: "id", client_secret: nil)
      assert {:error, :missing_client_secret} = HTTPClient.fetch_track("test123")
    end

    test "returns error when client_id is empty string" do
      Application.put_env(:sound_forge, :spotify, client_id: "", client_secret: "secret")
      assert {:error, :missing_client_id} = HTTPClient.fetch_track("test123")
    end

    test "returns error when client_secret is empty string" do
      Application.put_env(:sound_forge, :spotify, client_id: "id", client_secret: "")
      assert {:error, :missing_client_secret} = HTTPClient.fetch_track("test123")
    end
  end

  describe "token caching" do
    test "caches token in ETS" do
      HTTPClient.init()

      expires_at = System.system_time(:second) + 3500
      :ets.insert(@token_table, {:access_token, "test_token", expires_at})

      assert [{:access_token, "test_token", ^expires_at}] =
               :ets.lookup(@token_table, :access_token)
    end

    test "uses cached token instead of requesting new one" do
      HTTPClient.init()

      # Pre-cache a valid token
      expires_at = System.system_time(:second) + 3500
      :ets.insert(@token_table, {:access_token, "cached_token", expires_at})

      # Stub only the API request (token request should NOT be called)
      Req.Test.stub(SoundForge.Spotify.HTTPClient, fn conn ->
        # Verify the cached token is used in the Authorization header
        [auth] = Plug.Conn.get_req_header(conn, "authorization")
        assert auth == "Bearer cached_token"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "track123", "name" => "Cached Hit"}))
      end)

      assert {:ok, %{"id" => "track123", "name" => "Cached Hit"}} =
               HTTPClient.fetch_track("track123")
    end

    test "expired token triggers new token request" do
      HTTPClient.init()

      # Insert an expired token
      expired_at = System.system_time(:second) - 10
      :ets.insert(@token_table, {:access_token, "expired_token", expired_at})

      request_count = :counters.new(1, [:atomics])

      Req.Test.stub(SoundForge.Spotify.HTTPClient, fn conn ->
        :counters.add(request_count, 1, 1)

        case conn.request_path do
          # Token endpoint -- the expired token should force a new request here
          "/api/token" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"access_token" => "fresh_token"}))

          # API endpoint
          _ ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "track123"}))
        end
      end)

      assert {:ok, %{"id" => "track123"}} = HTTPClient.fetch_track("track123")
      # Both token + API requests should have been made
      assert :counters.get(request_count, 1) == 2
    end

    test "empty ETS table returns no cached token" do
      HTTPClient.init()
      assert [] = :ets.lookup(@token_table, :access_token)
    end
  end

  describe "fetch_track/1" do
    test "returns track data on successful response" do
      track_data = %{
        "id" => "abc123",
        "name" => "Test Song",
        "artists" => [%{"name" => "Test Artist"}],
        "album" => %{"name" => "Test Album"}
      }

      Req.Test.stub(SoundForge.Spotify.HTTPClient, fn conn ->
        case conn.request_path do
          "/api/token" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"access_token" => "test_token"}))

          "/v1/tracks/abc123" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(track_data))
        end
      end)

      assert {:ok, ^track_data} = HTTPClient.fetch_track("abc123")
    end

    test "returns error on 404 response" do
      Req.Test.stub(SoundForge.Spotify.HTTPClient, fn conn ->
        case conn.request_path do
          "/api/token" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"access_token" => "test_token"}))

          "/v1/tracks/" <> _id ->
            body = %{"error" => %{"status" => 404, "message" => "Not found"}}

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(404, Jason.encode!(body))
        end
      end)

      assert {:error, {:api_error, 404, _body}} = HTTPClient.fetch_track("nonexistent")
    end

    test "returns error on 429 rate limit response" do
      # Pre-cache a token so the test only hits the API endpoint
      HTTPClient.init()
      expires_at = System.system_time(:second) + 3500
      :ets.insert(@token_table, {:access_token, "test_token", expires_at})

      Req.Test.stub(SoundForge.Spotify.HTTPClient, fn conn ->
        body = %{"error" => %{"status" => 429, "message" => "Rate limit exceeded"}}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.put_resp_header("retry-after", "0")
        |> Plug.Conn.send_resp(429, Jason.encode!(body))
      end)

      assert {:error, {:api_error, 429, _body}} = HTTPClient.fetch_track("rate_limited")
    end
  end

  describe "fetch_album/1" do
    test "returns album data on success" do
      album_data = %{"id" => "album123", "name" => "Test Album", "tracks" => %{"items" => []}}

      Req.Test.stub(SoundForge.Spotify.HTTPClient, fn conn ->
        case conn.request_path do
          "/api/token" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"access_token" => "test_token"}))

          "/v1/albums/album123" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(album_data))
        end
      end)

      assert {:ok, ^album_data} = HTTPClient.fetch_album("album123")
    end

    test "returns error with missing credentials" do
      Application.put_env(:sound_forge, :spotify, client_id: nil, client_secret: nil)
      assert {:error, :missing_client_id} = HTTPClient.fetch_album("album123")
    end
  end

  describe "fetch_playlist/1" do
    test "returns playlist data on success" do
      playlist_data = %{
        "id" => "playlist456",
        "name" => "Test Playlist",
        "tracks" => %{"items" => []}
      }

      Req.Test.stub(SoundForge.Spotify.HTTPClient, fn conn ->
        case conn.request_path do
          "/api/token" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"access_token" => "test_token"}))

          "/v1/playlists/playlist456" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(playlist_data))
        end
      end)

      assert {:ok, ^playlist_data} = HTTPClient.fetch_playlist("playlist456")
    end

    test "returns error with missing credentials" do
      Application.put_env(:sound_forge, :spotify, client_id: nil, client_secret: nil)
      assert {:error, :missing_client_id} = HTTPClient.fetch_playlist("playlist456")
    end
  end

  describe "token request failures" do
    test "returns error when token endpoint returns 401" do
      Req.Test.stub(SoundForge.Spotify.HTTPClient, fn conn ->
        body = %{"error" => "invalid_client", "error_description" => "Invalid client secret"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(body))
      end)

      assert {:error, {:token_error, 401, _body}} = HTTPClient.fetch_track("test123")
    end

    test "returns error when token endpoint is unreachable" do
      Req.Test.stub(SoundForge.Spotify.HTTPClient, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %Req.TransportError{reason: :econnrefused}} =
               HTTPClient.fetch_track("test123")
    end
  end
end
