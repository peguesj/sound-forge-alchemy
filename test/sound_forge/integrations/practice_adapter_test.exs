defmodule SoundForge.Integrations.Melodics.PracticeAdapterTest do
  @moduledoc """
  Tests for PracticeAdapter: pure function coverage + DB-backed suggest_stems/practice_stats.
  """
  use SoundForge.DataCase

  alias SoundForge.Integrations.Melodics.PracticeAdapter
  alias SoundForge.Integrations.Melodics.MelodicsSession
  alias SoundForge.Repo

  defp insert_session!(user_id, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %MelodicsSession{}
    |> MelodicsSession.changeset(
      Map.merge(%{lesson_name: "Test", user_id: user_id, practiced_at: now}, attrs)
    )
    |> Repo.insert!()
  end

  describe "map_instrument_to_category/1" do
    test "pads -> vocals" do
      assert PracticeAdapter.map_instrument_to_category("pads") == :vocals
    end

    test "pad -> vocals" do
      assert PracticeAdapter.map_instrument_to_category("pad") == :vocals
    end

    test "keys -> melody" do
      assert PracticeAdapter.map_instrument_to_category("keys") == :melody
    end

    test "keyboard -> melody" do
      assert PracticeAdapter.map_instrument_to_category("keyboard") == :melody
    end

    test "piano -> melody" do
      assert PracticeAdapter.map_instrument_to_category("piano") == :melody
    end

    test "synth -> melody" do
      assert PracticeAdapter.map_instrument_to_category("synth") == :melody
    end

    test "drums -> drums" do
      assert PracticeAdapter.map_instrument_to_category("drums") == :drums
    end

    test "drum -> drums" do
      assert PracticeAdapter.map_instrument_to_category("drum") == :drums
    end

    test "bass -> bass" do
      assert PracticeAdapter.map_instrument_to_category("bass") == :bass
    end

    test "guitar -> other" do
      assert PracticeAdapter.map_instrument_to_category("guitar") == :other
    end

    test "nil -> other" do
      assert PracticeAdapter.map_instrument_to_category(nil) == :other
    end

    test "unknown instrument -> other" do
      assert PracticeAdapter.map_instrument_to_category("theremin") == :other
    end

    test "case insensitive" do
      assert PracticeAdapter.map_instrument_to_category("DRUMS") == :drums
      assert PracticeAdapter.map_instrument_to_category("Keys") == :melody
    end

    test "trims whitespace" do
      assert PracticeAdapter.map_instrument_to_category("  bass  ") == :bass
    end
  end

  describe "difficulty_from_accuracy/1" do
    test "nil -> matched" do
      assert PracticeAdapter.difficulty_from_accuracy(nil) == :matched
    end

    test "below 60 -> simple" do
      assert PracticeAdapter.difficulty_from_accuracy(0.0) == :simple
      assert PracticeAdapter.difficulty_from_accuracy(59.9) == :simple
    end

    test "exactly 60 -> matched" do
      assert PracticeAdapter.difficulty_from_accuracy(60.0) == :matched
    end

    test "between 60 and 85 -> matched" do
      assert PracticeAdapter.difficulty_from_accuracy(72.5) == :matched
      assert PracticeAdapter.difficulty_from_accuracy(85.0) == :matched
    end

    test "above 85 -> complex" do
      assert PracticeAdapter.difficulty_from_accuracy(85.1) == :complex
      assert PracticeAdapter.difficulty_from_accuracy(100.0) == :complex
    end
  end

  describe "suggest_stems/2" do
    test "returns empty for user with no sessions" do
      user = SoundForge.AccountsFixtures.user_fixture()
      assert PracticeAdapter.suggest_stems(user.id) == []
    end

    test "groups by instrument and returns suggestions" do
      user = SoundForge.AccountsFixtures.user_fixture()

      insert_session!(user.id, %{instrument: "keys", accuracy: 90.0})
      insert_session!(user.id, %{instrument: "keys", accuracy: 88.0})
      insert_session!(user.id, %{instrument: "drums", accuracy: 50.0})

      suggestions = PracticeAdapter.suggest_stems(user.id)
      assert length(suggestions) == 2

      cats = Enum.map(suggestions, &elem(&1, 0))
      diffs = Enum.map(suggestions, &elem(&1, 1))

      assert :melody in cats
      assert :drums in cats
      assert :complex in diffs
      assert :simple in diffs
    end

    test "sorted by session count descending" do
      user = SoundForge.AccountsFixtures.user_fixture()

      for _ <- 1..3, do: insert_session!(user.id, %{instrument: "drums", accuracy: 75.0})
      insert_session!(user.id, %{instrument: "bass", accuracy: 75.0})

      suggestions = PracticeAdapter.suggest_stems(user.id)
      [first | _] = suggestions
      assert elem(first, 0) == :drums
    end

    test "handles sessions with nil accuracy" do
      user = SoundForge.AccountsFixtures.user_fixture()
      insert_session!(user.id, %{instrument: "keys"})

      suggestions = PracticeAdapter.suggest_stems(user.id)
      assert length(suggestions) == 1
      {_cat, diff, meta} = hd(suggestions)
      assert diff == :matched
      assert meta.avg_accuracy == nil
    end

    test "handles sessions with nil instrument" do
      user = SoundForge.AccountsFixtures.user_fixture()
      insert_session!(user.id, %{accuracy: 70.0})

      suggestions = PracticeAdapter.suggest_stems(user.id)
      assert length(suggestions) >= 1
    end
  end

  describe "practice_stats/1" do
    test "returns stats with suggestions for user with sessions" do
      user = SoundForge.AccountsFixtures.user_fixture()

      insert_session!(user.id, %{instrument: "keys", accuracy: 92.0, bpm: 120})
      insert_session!(user.id, %{instrument: "drums", accuracy: 45.0, bpm: 100})

      stats = PracticeAdapter.practice_stats(user.id)
      assert is_list(stats.stem_suggestions)
      assert stats.strongest_category == :melody
      assert stats.weakest_category == :drums
      assert stats.total_sessions == 2
    end

    test "returns nil strongest/weakest when no complex/simple" do
      user = SoundForge.AccountsFixtures.user_fixture()

      insert_session!(user.id, %{instrument: "keys", accuracy: 72.0})

      stats = PracticeAdapter.practice_stats(user.id)
      assert stats.strongest_category == nil
      assert stats.weakest_category == nil
    end

    test "returns empty stats for user with no sessions" do
      user = SoundForge.AccountsFixtures.user_fixture()
      stats = PracticeAdapter.practice_stats(user.id)
      assert stats.stem_suggestions == []
      assert stats.strongest_category == nil
      assert stats.weakest_category == nil
    end
  end
end
