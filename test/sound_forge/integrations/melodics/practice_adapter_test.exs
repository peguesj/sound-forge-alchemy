defmodule SoundForge.Integrations.Melodics.PracticeAdapterTest do
  use SoundForge.DataCase

  alias SoundForge.Integrations.Melodics.PracticeAdapter

  import SoundForge.AccountsFixtures

  describe "map_instrument_to_category/1" do
    test "maps pads to vocals" do
      assert PracticeAdapter.map_instrument_to_category("pads") == :vocals
      assert PracticeAdapter.map_instrument_to_category("pad") == :vocals
    end

    test "maps keyboard instruments to melody" do
      assert PracticeAdapter.map_instrument_to_category("keys") == :melody
      assert PracticeAdapter.map_instrument_to_category("keyboard") == :melody
      assert PracticeAdapter.map_instrument_to_category("piano") == :melody
      assert PracticeAdapter.map_instrument_to_category("synth") == :melody
    end

    test "maps drums to drums" do
      assert PracticeAdapter.map_instrument_to_category("drums") == :drums
      assert PracticeAdapter.map_instrument_to_category("drum") == :drums
    end

    test "maps bass to bass" do
      assert PracticeAdapter.map_instrument_to_category("bass") == :bass
    end

    test "maps guitar to other" do
      assert PracticeAdapter.map_instrument_to_category("guitar") == :other
    end

    test "maps nil to other" do
      assert PracticeAdapter.map_instrument_to_category(nil) == :other
    end

    test "maps unknown instrument to other" do
      assert PracticeAdapter.map_instrument_to_category("theremin") == :other
    end

    test "is case-insensitive" do
      assert PracticeAdapter.map_instrument_to_category("DRUMS") == :drums
      assert PracticeAdapter.map_instrument_to_category("Piano") == :melody
    end
  end

  describe "difficulty_from_accuracy/1" do
    test "nil returns matched" do
      assert PracticeAdapter.difficulty_from_accuracy(nil) == :matched
    end

    test "low accuracy returns simple" do
      assert PracticeAdapter.difficulty_from_accuracy(30.0) == :simple
      assert PracticeAdapter.difficulty_from_accuracy(59.9) == :simple
    end

    test "mid accuracy returns matched" do
      assert PracticeAdapter.difficulty_from_accuracy(60.0) == :matched
      assert PracticeAdapter.difficulty_from_accuracy(75.0) == :matched
      assert PracticeAdapter.difficulty_from_accuracy(85.0) == :matched
    end

    test "high accuracy returns complex" do
      assert PracticeAdapter.difficulty_from_accuracy(85.1) == :complex
      assert PracticeAdapter.difficulty_from_accuracy(100.0) == :complex
    end
  end

  describe "suggest_stems/2" do
    test "returns empty list for user with no sessions" do
      user = user_fixture()
      result = PracticeAdapter.suggest_stems(user.id)
      assert result == []
    end
  end

  describe "practice_stats/1" do
    test "returns stats map for user with no sessions" do
      user = user_fixture()
      result = PracticeAdapter.practice_stats(user.id)
      assert is_map(result)
      assert result.stem_suggestions == []
      assert is_nil(result.strongest_category)
      assert is_nil(result.weakest_category)
    end
  end
end
