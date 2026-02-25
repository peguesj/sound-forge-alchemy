defmodule SoundForge.UAT do
  @moduledoc """
  UAT helpers — only available in :dev and :test environments.

  Provides fixture seeding, test data teardown, and named scenario runners
  for use from the Prototype sandbox (/prototype?tab=uat).

  All UAT-created records are identifiable by the "UAT Test" title prefix
  and "uat_" email prefix so they can be bulk-deleted with `clear_test_data/0`.
  """

  if Mix.env() not in [:dev, :test] do
    @doc "Not available in production."
    def seed_test_track(_user_id), do: raise("UAT module not available in production")

    @doc "Not available in production."
    def seed_test_user(_role \\ :user), do: raise("UAT module not available in production")

    @doc "Not available in production."
    def clear_test_data(), do: raise("UAT module not available in production")

    @doc "Not available in production."
    def run_scenario(_name, _user_id), do: raise("UAT module not available in production")
  else
    import Ecto.Query

    alias SoundForge.Repo
    alias SoundForge.Music.Track
    alias SoundForge.Accounts.User

    @doc """
    Creates a UAT test track in :pending state for the given `user_id`.

    Returns `{:ok, %Track{}}` or `{:error, changeset}`.
    """
    def seed_test_track(user_id) do
      suffix = System.unique_integer([:positive])

      %Track{}
      |> Track.changeset(%{
        title: "UAT Test Track #{suffix}",
        artist: "UAT Artist",
        album: "UAT Album",
        user_id: user_id,
        spotify_id: nil,
        spotify_url: nil,
        duration: 180
      })
      |> Repo.insert()
    end

    @doc """
    Creates a UAT test user with the given role.

    Returns `{:ok, %User{}}` or `{:error, changeset}`.
    """
    def seed_test_user(role \\ :user) do
      suffix = System.unique_integer([:positive])

      %User{}
      |> Ecto.Changeset.change(%{
        email: "uat_#{suffix}@test.com",
        hashed_password: Bcrypt.hash_pwd_salt("uat_password_123!"),
        role: role,
        confirmed_at: DateTime.utc_now(:second)
      })
      |> Repo.insert()
    end

    @doc """
    Removes all UAT-seeded records (tracks whose title starts with "UAT Test"
    and users whose email matches the "uat_*@test.com" pattern).

    Returns `:ok`.
    """
    def clear_test_data() do
      Repo.delete_all(from t in Track, where: like(t.title, "UAT Test%"))
      Repo.delete_all(from u in User, where: like(u.email, "uat_%@test.com"))
      :ok
    end

    @doc """
    Runs a named UAT scenario for `user_id`.

    Returns `{:ok, resource}` or `{:error, reason}`.

    ## Scenarios

    - `"import_spotify_track"` — seeds a pending UAT track
    - `"run_stem_separation"` — seeds a track and enqueues a stem separation job
    """
    def run_scenario("import_spotify_track", user_id) do
      seed_test_track(user_id)
    end

    def run_scenario("run_stem_separation", user_id) do
      with {:ok, track} <- seed_test_track(user_id) do
        _job =
          %{"track_id" => track.id, "model" => "htdemucs"}
          |> SoundForge.Jobs.DemuserWorker.new()
          |> Oban.insert()

        {:ok, track}
      end
    end

    def run_scenario(name, _user_id) do
      {:error, "Unknown scenario: #{name}"}
    end
  end
end
