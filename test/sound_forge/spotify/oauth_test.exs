defmodule SoundForge.Spotify.OAuthTest do
  use SoundForge.DataCase, async: true

  alias SoundForge.Spotify.OAuth
  alias SoundForge.Accounts.SpotifyOAuthToken

  import SoundForge.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "generate_state/0" do
    test "returns a random string" do
      state1 = OAuth.generate_state()
      state2 = OAuth.generate_state()
      assert is_binary(state1)
      assert byte_size(state1) > 10
      assert state1 != state2
    end
  end

  describe "authorize_url/1" do
    test "builds a valid Spotify authorization URL" do
      url = OAuth.authorize_url("test_state")
      assert String.starts_with?(url, "https://accounts.spotify.com/authorize?")
      assert String.contains?(url, "response_type=code")
      assert String.contains?(url, "state=test_state")
      assert String.contains?(url, "scope=")
    end
  end

  describe "save_token/2 and linked?/1" do
    test "saves encrypted tokens", %{user: user} do
      token_data = %{
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        token_type: "Bearer",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second),
        scopes: "playlist-read-private"
      }

      assert {:ok, %SpotifyOAuthToken{} = saved} = OAuth.save_token(user.id, token_data)
      assert saved.user_id == user.id
      # Tokens are encrypted, so they should differ from plaintext
      assert saved.access_token != "test_access_token"
      assert saved.refresh_token != "test_refresh_token"
    end

    test "upserts on duplicate user_id", %{user: user} do
      expires = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)

      token_data1 = %{
        access_token: "first_token",
        refresh_token: "first_refresh",
        expires_at: expires
      }

      token_data2 = %{
        access_token: "second_token",
        refresh_token: "second_refresh",
        expires_at: expires
      }

      {:ok, _} = OAuth.save_token(user.id, token_data1)
      {:ok, _} = OAuth.save_token(user.id, token_data2)

      assert Repo.aggregate(SpotifyOAuthToken, :count, :id) == 1
    end
  end

  describe "linked?/1" do
    test "returns false when no token exists", %{user: user} do
      refute OAuth.linked?(user.id)
    end

    test "returns true when token exists", %{user: user} do
      token_data = %{
        access_token: "test",
        refresh_token: "test",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)
      }

      {:ok, _} = OAuth.save_token(user.id, token_data)
      assert OAuth.linked?(user.id)
    end
  end

  describe "unlink/1" do
    test "removes token", %{user: user} do
      token_data = %{
        access_token: "test",
        refresh_token: "test",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)
      }

      {:ok, _} = OAuth.save_token(user.id, token_data)
      assert OAuth.linked?(user.id)

      {:ok, _} = OAuth.unlink(user.id)
      refute OAuth.linked?(user.id)
    end

    test "returns ok when no token exists", %{user: user} do
      assert {:ok, nil} = OAuth.unlink(user.id)
    end
  end

  describe "expired?" do
    test "returns true for expired token" do
      token = %SpotifyOAuthToken{
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)
      }

      assert SpotifyOAuthToken.expired?(token)
    end

    test "returns false for valid token" do
      token = %SpotifyOAuthToken{
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)
      }

      refute SpotifyOAuthToken.expired?(token)
    end
  end

  describe "get_valid_access_token/1" do
    test "returns :not_linked when no token exists", %{user: user} do
      assert {:error, :not_linked} = OAuth.get_valid_access_token(user.id)
    end

    test "returns decrypted token when not expired", %{user: user} do
      token_data = %{
        access_token: "my_access_token",
        refresh_token: "my_refresh_token",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)
      }

      {:ok, _} = OAuth.save_token(user.id, token_data)
      assert {:ok, "my_access_token"} = OAuth.get_valid_access_token(user.id)
    end
  end
end
