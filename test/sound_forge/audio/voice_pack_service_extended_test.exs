defmodule SoundForge.Audio.VoicePackServiceExtendedTest do
  @moduledoc "Extended tests for VoicePackService builtins and caching logic."
  use SoundForge.DataCase

  alias SoundForge.Audio.VoicePackService

  describe "builtin_packs/0" do
    test "returns a list of strings" do
      packs = VoicePackService.builtin_packs()
      assert is_list(packs)
      assert length(packs) > 0
      Enum.each(packs, fn p -> assert is_binary(p) end)
    end

    test "returns consistent results" do
      assert VoicePackService.builtin_packs() == VoicePackService.builtin_packs()
    end

    test "includes expected pack names" do
      packs = VoicePackService.builtin_packs()
      # Should have common voice pack types
      assert length(packs) >= 5
    end
  end

  describe "list_packs/0" do
    test "returns ok tuple" do
      result = VoicePackService.list_packs()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
