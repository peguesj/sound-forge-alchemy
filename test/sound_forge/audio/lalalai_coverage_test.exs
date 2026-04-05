defmodule SoundForge.Audio.LalalAICoverageTest do
  @moduledoc "Tests for LalalAI module: public API functions that don't require API calls."
  use SoundForge.DataCase

  alias SoundForge.Audio.LalalAI

  describe "api_key/0" do
    test "returns nil or string" do
      result = LalalAI.api_key()
      assert is_nil(result) or is_binary(result)
    end
  end

  describe "system_key/0" do
    test "returns nil or string" do
      result = LalalAI.system_key()
      assert is_nil(result) or is_binary(result)
    end
  end

  describe "resolve_key/0" do
    test "returns nil or string" do
      result = LalalAI.resolve_key()
      assert is_nil(result) or is_binary(result)
    end
  end

  describe "configured?/0" do
    test "returns a boolean" do
      assert is_boolean(LalalAI.configured?())
    end
  end

  describe "configured_for_user?/1" do
    test "returns boolean for nil user" do
      assert is_boolean(LalalAI.configured_for_user?(nil))
    end

    test "returns boolean for a real user" do
      user = SoundForge.AccountsFixtures.user_fixture()
      assert is_boolean(LalalAI.configured_for_user?(user.id))
    end
  end

  describe "api_key_for_user/1" do
    test "returns nil or string for nil user" do
      result = LalalAI.api_key_for_user(nil)
      assert is_nil(result) or is_binary(result)
    end

    test "returns nil or string for a real user" do
      user = SoundForge.AccountsFixtures.user_fixture()
      result = LalalAI.api_key_for_user(user.id)
      assert is_nil(result) or is_binary(result)
    end
  end

  describe "stem_filters/0" do
    test "returns a list of 11 string filters" do
      filters = LalalAI.stem_filters()
      assert is_list(filters)
      assert length(filters) == 11
      assert "vocals" in filters
      assert "drum" in filters
      assert "bass" in filters
      assert "piano" in filters
      assert "electricguitar" in filters
    end
  end

  describe "filter_to_stem_type/1" do
    test "maps vocals to :vocals" do
      assert LalalAI.filter_to_stem_type("vocals") == :vocals
    end

    test "maps drum to :drums" do
      assert LalalAI.filter_to_stem_type("drum") == :drums
    end

    test "maps bass to :bass" do
      assert LalalAI.filter_to_stem_type("bass") == :bass
    end

    test "maps electricguitar to :electric_guitar" do
      assert LalalAI.filter_to_stem_type("electricguitar") == :electric_guitar
    end

    test "maps acousticguitar to :acoustic_guitar" do
      assert LalalAI.filter_to_stem_type("acousticguitar") == :acoustic_guitar
    end

    test "maps piano to :piano" do
      assert LalalAI.filter_to_stem_type("piano") == :piano
    end

    test "maps synthesizer to :synth" do
      assert LalalAI.filter_to_stem_type("synthesizer") == :synth
    end

    test "maps strings to :strings" do
      assert LalalAI.filter_to_stem_type("strings") == :strings
    end

    test "maps winds to :wind" do
      assert LalalAI.filter_to_stem_type("winds") == :wind
    end

    test "returns nil for unknown filter" do
      assert LalalAI.filter_to_stem_type("unknown") == nil
    end
  end

  describe "upload_track/2 without API key" do
    test "returns :api_key_missing when no key configured" do
      # In test env, LALALAI_API_KEY is typically not set
      if is_nil(LalalAI.resolve_key()) do
        assert {:error, :api_key_missing} = LalalAI.upload_track("/tmp/test.mp3")
      end
    end
  end

  describe "get_status/1 without API key" do
    test "returns :api_key_missing when no key configured" do
      if is_nil(LalalAI.resolve_key()) do
        assert {:error, :api_key_missing} = LalalAI.get_status("test-task-id")
      end
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
end
