defmodule SoundForge.Accounts.SpotifyOAuthTokenTest do
  use SoundForge.DataCase, async: true

  alias SoundForge.Accounts.SpotifyOAuthToken

  import SoundForge.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "changeset/2" do
    test "valid changeset with all required fields", %{user: user} do
      attrs = %{
        access_token: "access_abc",
        refresh_token: "refresh_xyz",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        user_id: user.id
      }

      changeset = SpotifyOAuthToken.changeset(%SpotifyOAuthToken{}, attrs)
      assert changeset.valid?
    end

    test "requires access_token" do
      changeset =
        SpotifyOAuthToken.changeset(%SpotifyOAuthToken{}, %{
          refresh_token: "ref",
          expires_at: DateTime.utc_now(),
          user_id: 1
        })

      assert %{access_token: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires refresh_token" do
      changeset =
        SpotifyOAuthToken.changeset(%SpotifyOAuthToken{}, %{
          access_token: "acc",
          expires_at: DateTime.utc_now(),
          user_id: 1
        })

      assert %{refresh_token: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires expires_at" do
      changeset =
        SpotifyOAuthToken.changeset(%SpotifyOAuthToken{}, %{
          access_token: "acc",
          refresh_token: "ref",
          user_id: 1
        })

      assert %{expires_at: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires user_id" do
      changeset =
        SpotifyOAuthToken.changeset(%SpotifyOAuthToken{}, %{
          access_token: "acc",
          refresh_token: "ref",
          expires_at: DateTime.utc_now()
        })

      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults token_type to Bearer" do
      changeset =
        SpotifyOAuthToken.changeset(%SpotifyOAuthToken{}, %{
          access_token: "acc",
          refresh_token: "ref",
          expires_at: DateTime.utc_now(),
          user_id: 1
        })

      assert Ecto.Changeset.get_field(changeset, :token_type) == "Bearer"
    end

    test "allows setting scopes" do
      changeset =
        SpotifyOAuthToken.changeset(%SpotifyOAuthToken{}, %{
          access_token: "acc",
          refresh_token: "ref",
          expires_at: DateTime.utc_now(),
          user_id: 1,
          scopes: "streaming user-read-email"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :scopes) == "streaming user-read-email"
    end
  end

  describe "expired?/1" do
    test "returns true when expires_at is in the past" do
      token = %SpotifyOAuthToken{
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      }

      assert SpotifyOAuthToken.expired?(token)
    end

    test "returns false when expires_at is in the future" do
      token = %SpotifyOAuthToken{
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      refute SpotifyOAuthToken.expired?(token)
    end

    test "returns true for non-struct input" do
      assert SpotifyOAuthToken.expired?(nil)
      assert SpotifyOAuthToken.expired?(%{})
    end
  end
end
