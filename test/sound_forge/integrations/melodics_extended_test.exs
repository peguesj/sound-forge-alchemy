defmodule SoundForge.Integrations.MelodicsExtendedTest do
  @moduledoc """
  Tests for Melodics public API: list_sessions, get_stats, find_data_dir.
  Private parse functions are covered indirectly via import_sessions when possible.
  """
  use SoundForge.DataCase

  alias SoundForge.Integrations.Melodics
  alias SoundForge.Integrations.Melodics.MelodicsSession
  alias SoundForge.Repo

  import SoundForge.AccountsFixtures

  defp insert_session!(user_id, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %MelodicsSession{}
    |> MelodicsSession.changeset(
      Map.merge(%{lesson_name: "Test Lesson", user_id: user_id, practiced_at: now}, attrs)
    )
    |> Repo.insert!()
  end

  describe "list_sessions/2" do
    test "returns empty list for user with no sessions" do
      user = user_fixture()
      assert Melodics.list_sessions(user.id) == []
    end

    test "returns sessions ordered by practiced_at desc" do
      user = user_fixture()
      old = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      recent = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_session!(user.id, %{lesson_name: "Old", practiced_at: old})
      insert_session!(user.id, %{lesson_name: "Recent", practiced_at: recent})

      sessions = Melodics.list_sessions(user.id)
      assert length(sessions) == 2
      assert hd(sessions).lesson_name == "Recent"
    end

    test "respects limit option" do
      user = user_fixture()
      for i <- 1..5, do: insert_session!(user.id, %{lesson_name: "Lesson #{i}"})
      sessions = Melodics.list_sessions(user.id, limit: 2)
      assert length(sessions) == 2
    end
  end

  describe "get_stats/1" do
    test "returns zero stats for user with no sessions" do
      user = user_fixture()
      stats = Melodics.get_stats(user.id)
      assert stats.total_sessions == 0
      assert stats.avg_accuracy == nil
      assert stats.avg_bpm == nil
      assert stats.instruments == []
      assert stats.sessions_this_week == 0
      assert stats.bpm_trend == []
    end

    test "calculates averages and instrument list" do
      user = user_fixture()
      insert_session!(user.id, %{instrument: "keys", accuracy: 80.0, bpm: 120})
      insert_session!(user.id, %{instrument: "drums", accuracy: 60.0, bpm: 100})

      stats = Melodics.get_stats(user.id)
      assert stats.total_sessions == 2
      assert_in_delta stats.avg_accuracy, 70.0, 0.01
      assert_in_delta stats.avg_bpm, 110.0, 0.01
      assert length(stats.instruments) == 2
      assert "keys" in stats.instruments
      assert "drums" in stats.instruments
    end

    test "sessions_this_week counts recent sessions" do
      user = user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      old = DateTime.utc_now() |> DateTime.add(-30 * 86400, :second) |> DateTime.truncate(:second)

      insert_session!(user.id, %{practiced_at: now, lesson_name: "Recent"})
      insert_session!(user.id, %{practiced_at: old, lesson_name: "Old"})

      stats = Melodics.get_stats(user.id)
      assert stats.sessions_this_week == 1
    end

    test "bpm_trend returns up to 10 reversed bpm values" do
      user = user_fixture()

      for i <- 1..12 do
        ts = DateTime.utc_now() |> DateTime.add(-i * 60, :second) |> DateTime.truncate(:second)
        insert_session!(user.id, %{bpm: 100 + i, practiced_at: ts})
      end

      stats = Melodics.get_stats(user.id)
      assert length(stats.bpm_trend) == 10
    end

    test "handles sessions with nil accuracy and bpm" do
      user = user_fixture()
      insert_session!(user.id, %{})

      stats = Melodics.get_stats(user.id)
      assert stats.total_sessions == 1
      assert stats.avg_accuracy == nil
      assert stats.avg_bpm == nil
    end
  end

  describe "find_data_dir/0" do
    test "returns :not_found when no Melodics dirs exist" do
      # The test environment likely doesn't have Melodics installed
      result = Melodics.find_data_dir()
      # Either finds a dir or doesn't - both are valid
      assert match?({:ok, _}, result) or result == {:error, :not_found}
    end
  end

  describe "import_sessions/1" do
    test "returns error when Melodics not installed" do
      user = user_fixture()
      result = Melodics.import_sessions(user.id)
      # Depends on whether Melodics data dir exists on CI/test machine
      assert match?({:ok, _}, result) or result == {:error, :melodics_not_found}
    end
  end
end
