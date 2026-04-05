defmodule Mix.Tasks.ModulesTest do
  use ExUnit.Case, async: true

  describe "Mix.Tasks.BackfillAlbums" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Mix.Tasks.BackfillAlbums)
    end

    test "run/1 is defined" do
      assert {:run, 1} in Mix.Tasks.BackfillAlbums.__info__(:functions)
    end
  end

  describe "Mix.Tasks.FixDownloadPaths" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Mix.Tasks.FixDownloadPaths)
    end

    test "run/1 is defined" do
      assert {:run, 1} in Mix.Tasks.FixDownloadPaths.__info__(:functions)
    end
  end

  describe "Mix.Tasks.Sfa.Touchosc.Generate" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Mix.Tasks.Sfa.Touchosc.Generate)
    end

    test "run/1 is defined" do
      assert {:run, 1} in Mix.Tasks.Sfa.Touchosc.Generate.__info__(:functions)
    end
  end

  describe "Mix.Tasks.PromoteAdmin" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Mix.Tasks.PromoteAdmin)
    end

    test "run/1 is defined" do
      assert {:run, 1} in Mix.Tasks.PromoteAdmin.__info__(:functions)
    end
  end
end
