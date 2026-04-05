defmodule SoundForge.Audio.VoicePackServiceCoverageTest do
  @moduledoc "Tests for VoicePackService: builtin_packs and basic behavior."
  use SoundForge.DataCase

  alias SoundForge.Audio.VoicePackService

  describe "builtin_packs/0" do
    test "returns exactly 7 packs" do
      packs = VoicePackService.builtin_packs()
      assert length(packs) == 7
    end

    test "all packs are strings" do
      packs = VoicePackService.builtin_packs()
      assert Enum.all?(packs, &is_binary/1)
    end

    test "contains known pack names" do
      packs = VoicePackService.builtin_packs()
      assert "ALEX_KAYE" in packs
      assert "VETRANA" in packs
      assert "NIK_ZEL" in packs
    end
  end

  describe "list_packs/0" do
    test "returns ok tuple or error tuple" do
      result = VoicePackService.list_packs()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
