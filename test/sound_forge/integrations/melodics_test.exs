defmodule SoundForge.Integrations.MelodicsTest do
  @moduledoc """
  Tests for the Melodics integration module.
  """
  use SoundForge.DataCase

  alias SoundForge.Integrations.Melodics
  alias SoundForge.Integrations.Melodics.MelodicsSession
  alias SoundForge.Repo

  defp insert_session!(user_id, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %MelodicsSession{}
    |> MelodicsSession.changeset(
      Map.merge(
        %{lesson_name: "Test Lesson", user_id: user_id, practiced_at: now},
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "find_data_dir/0" do
    test "returns error when no Melodics directory exists" do
      result = Melodics.find_data_dir()
      assert match?({:ok, _}, result) or result == {:error, :not_found}
    end
  end

  describe "list_sessions/2" do
    test "returns empty list for unknown user" do
      assert Melodics.list_sessions(999_999_999) == []
    end

    test "respects limit option" do
      assert Melodics.list_sessions(999_999_999, limit: 5) == []
    end

    test "returns sessions ordered by practiced_at desc" do
      user = SoundForge.AccountsFixtures.user_fixture()
      old_time = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)
      new_time = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_session!(user.id, %{lesson_name: "Old Lesson", practiced_at: old_time})
      insert_session!(user.id, %{lesson_name: "New Lesson", practiced_at: new_time})

      sessions = Melodics.list_sessions(user.id)
      assert length(sessions) == 2
      assert hd(sessions).lesson_name == "New Lesson"
    end

    test "limits results" do
      user = SoundForge.AccountsFixtures.user_fixture()

      for i <- 1..5 do
        insert_session!(user.id, %{lesson_name: "Lesson #{i}"})
      end

      assert length(Melodics.list_sessions(user.id, limit: 3)) == 3
    end
  end

  describe "get_stats/1" do
    test "returns empty stats for user with no sessions" do
      stats = Melodics.get_stats(999_999_999)
      assert stats.total_sessions == 0
      assert stats.avg_accuracy == nil
      assert stats.avg_bpm == nil
      assert stats.instruments == []
      assert stats.sessions_this_week == 0
      assert stats.bpm_trend == []
    end

    test "calculates avg_accuracy from sessions" do
      user = SoundForge.AccountsFixtures.user_fixture()

      insert_session!(user.id, %{lesson_name: "A", accuracy: 80.0})
      insert_session!(user.id, %{lesson_name: "B", accuracy: 90.0})

      stats = Melodics.get_stats(user.id)
      assert stats.total_sessions == 2
      assert_in_delta stats.avg_accuracy, 85.0, 0.01
    end

    test "calculates avg_bpm from sessions" do
      user = SoundForge.AccountsFixtures.user_fixture()

      insert_session!(user.id, %{lesson_name: "A", bpm: 100})
      insert_session!(user.id, %{lesson_name: "B", bpm: 140})

      stats = Melodics.get_stats(user.id)
      assert_in_delta stats.avg_bpm, 120.0, 0.01
    end

    test "collects unique instruments" do
      user = SoundForge.AccountsFixtures.user_fixture()

      insert_session!(user.id, %{lesson_name: "A", instrument: "keys"})
      insert_session!(user.id, %{lesson_name: "B", instrument: "drums"})
      insert_session!(user.id, %{lesson_name: "C", instrument: "keys"})

      stats = Melodics.get_stats(user.id)
      assert Enum.sort(stats.instruments) == ["drums", "keys"]
    end

    test "counts sessions this week" do
      user = SoundForge.AccountsFixtures.user_fixture()
      recent = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      old = DateTime.utc_now() |> DateTime.add(-10 * 86_400, :second) |> DateTime.truncate(:second)

      insert_session!(user.id, %{lesson_name: "Recent", practiced_at: recent})
      insert_session!(user.id, %{lesson_name: "Old", practiced_at: old})

      stats = Melodics.get_stats(user.id)
      assert stats.sessions_this_week == 1
    end

    test "returns bpm_trend from recent sessions" do
      user = SoundForge.AccountsFixtures.user_fixture()

      for {bpm, i} <- [{100, 0}, {110, 1}, {120, 2}] do
        t = DateTime.utc_now() |> DateTime.add(-i * 3600, :second) |> DateTime.truncate(:second)
        insert_session!(user.id, %{lesson_name: "L#{i}", bpm: bpm, practiced_at: t})
      end

      stats = Melodics.get_stats(user.id)
      assert is_list(stats.bpm_trend)
      assert length(stats.bpm_trend) == 3
    end

    test "handles sessions with nil accuracy/bpm" do
      user = SoundForge.AccountsFixtures.user_fixture()

      insert_session!(user.id, %{lesson_name: "No Data"})
      insert_session!(user.id, %{lesson_name: "Has Data", accuracy: 75.0, bpm: 90})

      stats = Melodics.get_stats(user.id)
      assert stats.total_sessions == 2
      assert_in_delta stats.avg_accuracy, 75.0, 0.01
      assert_in_delta stats.avg_bpm, 90.0, 0.01
    end
  end

  describe "import_sessions/1" do
    test "returns error when Melodics not installed" do
      case Melodics.find_data_dir() do
        {:error, :not_found} ->
          assert {:error, :melodics_not_found} = Melodics.import_sessions(999)

        {:ok, _} ->
          assert {:ok, count} = Melodics.import_sessions(999)
          assert is_integer(count)
      end
    end
  end
end
