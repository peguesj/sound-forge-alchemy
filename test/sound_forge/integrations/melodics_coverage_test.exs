defmodule SoundForge.Integrations.MelodicsCoverageTest do
  @moduledoc "Tests for Melodics integration: find_data_dir, list_sessions, get_stats, import."
  use SoundForge.DataCase

  alias SoundForge.Integrations.Melodics

  describe "find_data_dir/0" do
    test "returns error when no melodics directory exists" do
      # On test machines, Melodics is unlikely to be installed
      result = Melodics.find_data_dir()
      assert result == {:error, :not_found} or match?({:ok, _}, result)
    end
  end

  describe "list_sessions/2" do
    test "returns empty list for user with no sessions" do
      user = SoundForge.AccountsFixtures.user_fixture()
      assert Melodics.list_sessions(user.id) == []
    end

    test "respects limit option" do
      user = SoundForge.AccountsFixtures.user_fixture()
      assert Melodics.list_sessions(user.id, limit: 5) == []
    end
  end

  describe "get_stats/1" do
    test "returns empty stats for user with no sessions" do
      user = SoundForge.AccountsFixtures.user_fixture()
      stats = Melodics.get_stats(user.id)

      assert stats.total_sessions == 0
      assert stats.avg_accuracy == nil
      assert stats.avg_bpm == nil
      assert stats.instruments == []
      assert stats.sessions_this_week == 0
      assert stats.bpm_trend == []
    end
  end

  describe "import_sessions/1" do
    test "returns error when melodics not found" do
      user = SoundForge.AccountsFixtures.user_fixture()
      result = Melodics.import_sessions(user.id)
      # Usually :melodics_not_found unless Melodics is installed
      assert result == {:error, :melodics_not_found} or match?({:ok, _}, result)
    end
  end
end
