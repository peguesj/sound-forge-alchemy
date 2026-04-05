defmodule SoundForge.UATTest do
  use SoundForge.DataCase

  alias SoundForge.UAT

  import SoundForge.AccountsFixtures

  describe "seed_test_track/1" do
    test "creates a UAT test track" do
      user = user_fixture()
      assert {:ok, track} = UAT.seed_test_track(user.id)
      assert String.starts_with?(track.title, "UAT Test Track")
      assert track.artist == "UAT Artist"
      assert track.user_id == user.id
    end
  end

  describe "seed_test_user/1" do
    test "creates a UAT user with default role" do
      assert {:ok, user} = UAT.seed_test_user()
      assert user.role == :user
      assert String.starts_with?(user.email, "uat_")
    end

    test "creates a UAT user with custom role" do
      assert {:ok, user} = UAT.seed_test_user(:admin)
      assert user.role == :admin
    end
  end

  describe "clear_test_data/0" do
    test "removes UAT tracks and users" do
      user = user_fixture()
      UAT.seed_test_track(user.id)
      UAT.seed_test_user()

      assert :ok = UAT.clear_test_data()
    end
  end

  describe "run_scenario/2" do
    test "import_spotify_track scenario seeds a track" do
      user = user_fixture()
      assert {:ok, track} = UAT.run_scenario("import_spotify_track", user.id)
      assert String.starts_with?(track.title, "UAT Test Track")
    end

    test "unknown scenario returns error" do
      user = user_fixture()
      assert {:error, "Unknown scenario: nonexistent"} = UAT.run_scenario("nonexistent", user.id)
    end
  end
end
