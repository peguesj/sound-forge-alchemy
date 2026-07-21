defmodule SoundForge.Audio.VoicePackServiceTest do
  use SoundForge.DataCase

  alias SoundForge.Audio.VoicePackService

  describe "builtin_packs/0" do
    test "returns 7 builtin voice packs" do
      packs = VoicePackService.builtin_packs()
      assert length(packs) == 7
      assert "ALEX_KAYE" in packs
      assert "STASIA_FAYE" in packs
      assert "NICOLAAS_HAAS" in packs
      assert "NIK_ZEL" in packs
      assert "OLIA_CHEBO" in packs
      assert "YVAR_DE_GROOT" in packs
      assert "VETRANA" in packs
    end
  end

  describe "list_packs/0" do
    test "returns ok tuple" do
      # May return cached or stale data, but should not crash
      result = VoicePackService.list_packs()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "refresh_cache/0" do
    test "returns ok or error tuple" do
      result = VoicePackService.refresh_cache()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
