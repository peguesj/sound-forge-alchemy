defmodule SoundForge.Audio.LalalAITest do
  @moduledoc """
  Unit tests for LalalAI pure functions and configuration checks.
  Tests that do NOT require external API calls.
  """
  use SoundForge.DataCase

  alias SoundForge.Audio.LalalAI

  describe "stem_filters/0" do
    test "returns a list of string filter names" do
      filters = LalalAI.stem_filters()
      assert is_list(filters)
      assert "vocals" in filters
      assert "drum" in filters
      assert "bass" in filters
      assert "piano" in filters
      assert length(filters) == 11
    end
  end

  describe "configured?/0" do
    test "returns boolean" do
      result = LalalAI.configured?()
      assert is_boolean(result)
    end
  end

  describe "configured_for_user?/1" do
    test "returns boolean for nil user" do
      result = LalalAI.configured_for_user?(nil)
      assert is_boolean(result)
    end
  end

  describe "api_key_for_user/1" do
    test "returns nil or string for nil user" do
      result = LalalAI.api_key_for_user(nil)
      assert is_nil(result) or is_binary(result)
    end
  end

  describe "test_api_key/1" do
    test "returns error for empty string" do
      assert {:error, :empty_api_key} = LalalAI.test_api_key("")
    end

    test "returns error for nil" do
      assert {:error, :empty_api_key} = LalalAI.test_api_key(nil)
    end
  end

  describe "system_key/0" do
    test "returns nil or string" do
      result = LalalAI.system_key()
      assert is_nil(result) or is_binary(result)
    end
  end

  describe "filter_to_stem_type/1" do
    test "maps vocals" do
      assert LalalAI.filter_to_stem_type("vocals") == :vocals
    end

    test "maps drum" do
      assert LalalAI.filter_to_stem_type("drum") == :drums
    end

    test "maps bass" do
      assert LalalAI.filter_to_stem_type("bass") == :bass
    end

    test "maps electricguitar" do
      assert LalalAI.filter_to_stem_type("electricguitar") == :electric_guitar
    end

    test "maps acousticguitar" do
      assert LalalAI.filter_to_stem_type("acousticguitar") == :acoustic_guitar
    end

    test "maps piano" do
      assert LalalAI.filter_to_stem_type("piano") == :piano
    end

    test "maps synthesizer" do
      assert LalalAI.filter_to_stem_type("synthesizer") == :synth
    end

    test "maps strings" do
      assert LalalAI.filter_to_stem_type("strings") == :strings
    end

    test "maps winds" do
      assert LalalAI.filter_to_stem_type("winds") == :wind
    end

    test "maps noise" do
      assert LalalAI.filter_to_stem_type("noise") == :other
    end

    test "returns nil for unknown filter" do
      assert LalalAI.filter_to_stem_type("nonexistent") == nil
    end

    test "returns nil for empty string" do
      assert LalalAI.filter_to_stem_type("") == nil
    end
  end

  describe "api_key/0" do
    test "returns nil or string" do
      result = LalalAI.api_key()
      assert is_nil(result) or is_binary(result)
    end
  end

  describe "resolve_key/0" do
    test "returns nil or string" do
      result = LalalAI.resolve_key()
      assert is_nil(result) or is_binary(result)
    end
  end

  describe "api_key_for_user/1 with integer" do
    test "returns nil for nonexistent user" do
      result = LalalAI.api_key_for_user(999_999_999)
      assert is_nil(result) or is_binary(result)
    end
  end

  describe "configured_for_user?/1 with integer" do
    test "returns boolean for nonexistent user" do
      result = LalalAI.configured_for_user?(999_999_999)
      assert is_boolean(result)
    end
  end
end
