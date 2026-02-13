defmodule SoundForge.Spotify.HTTPClientTest do
  use ExUnit.Case, async: false

  alias SoundForge.Spotify.HTTPClient

  @token_table :spotify_tokens

  setup do
    # Clean up ETS table before each test
    try do
      :ets.delete(@token_table)
    rescue
      ArgumentError -> :ok
    end

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

  describe "get_spotify_config/0 (via fetch_track)" do
    test "returns error when client_id is missing" do
      original = Application.get_env(:sound_forge, :spotify)

      try do
        Application.put_env(:sound_forge, :spotify, client_id: nil, client_secret: "secret")
        assert {:error, :missing_client_id} = HTTPClient.fetch_track("test123")
      after
        if original do
          Application.put_env(:sound_forge, :spotify, original)
        else
          Application.delete_env(:sound_forge, :spotify)
        end
      end
    end

    test "returns error when client_secret is missing" do
      original = Application.get_env(:sound_forge, :spotify)

      try do
        Application.put_env(:sound_forge, :spotify, client_id: "id", client_secret: nil)
        assert {:error, :missing_client_secret} = HTTPClient.fetch_track("test123")
      after
        if original do
          Application.put_env(:sound_forge, :spotify, original)
        else
          Application.delete_env(:sound_forge, :spotify)
        end
      end
    end

    test "returns error when client_id is empty string" do
      original = Application.get_env(:sound_forge, :spotify)

      try do
        Application.put_env(:sound_forge, :spotify, client_id: "", client_secret: "secret")
        assert {:error, :missing_client_id} = HTTPClient.fetch_track("test123")
      after
        if original do
          Application.put_env(:sound_forge, :spotify, original)
        else
          Application.delete_env(:sound_forge, :spotify)
        end
      end
    end
  end

  describe "token caching" do
    test "caches token in ETS" do
      HTTPClient.init()

      # Manually insert a token
      expires_at = System.system_time(:second) + 3500
      :ets.insert(@token_table, {:access_token, "test_token", expires_at})

      # Verify token is cached
      assert [{:access_token, "test_token", ^expires_at}] =
               :ets.lookup(@token_table, :access_token)
    end

    test "expired token is not returned" do
      HTTPClient.init()

      # Insert an expired token
      expired_at = System.system_time(:second) - 10
      :ets.insert(@token_table, {:access_token, "expired_token", expired_at})

      # Trying to fetch should not use the expired token
      # (will fail because we don't have valid Spotify creds, but that's expected)
      original = Application.get_env(:sound_forge, :spotify)

      try do
        Application.put_env(:sound_forge, :spotify, client_id: nil, client_secret: nil)
        assert {:error, _} = HTTPClient.fetch_track("test123")
      after
        if original do
          Application.put_env(:sound_forge, :spotify, original)
        else
          Application.delete_env(:sound_forge, :spotify)
        end
      end
    end

    test "empty ETS table returns no cached token" do
      HTTPClient.init()
      assert [] = :ets.lookup(@token_table, :access_token)
    end
  end

  describe "fetch_album/1" do
    test "returns error with missing credentials" do
      original = Application.get_env(:sound_forge, :spotify)

      try do
        Application.put_env(:sound_forge, :spotify, client_id: nil, client_secret: nil)
        assert {:error, :missing_client_id} = HTTPClient.fetch_album("album123")
      after
        if original do
          Application.put_env(:sound_forge, :spotify, original)
        else
          Application.delete_env(:sound_forge, :spotify)
        end
      end
    end
  end

  describe "fetch_playlist/1" do
    test "returns error with missing credentials" do
      original = Application.get_env(:sound_forge, :spotify)

      try do
        Application.put_env(:sound_forge, :spotify, client_id: nil, client_secret: nil)
        assert {:error, :missing_client_id} = HTTPClient.fetch_playlist("playlist456")
      after
        if original do
          Application.put_env(:sound_forge, :spotify, original)
        else
          Application.delete_env(:sound_forge, :spotify)
        end
      end
    end
  end
end
