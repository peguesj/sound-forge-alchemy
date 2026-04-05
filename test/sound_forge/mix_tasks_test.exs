defmodule SoundForge.MixTasksTest do
  @moduledoc """
  Tests for Mix task modules: PromoteAdmin, Sfa.Touchosc.Generate.
  Tests module loading and function exports (Mix tasks depend on app.start
  which makes direct invocation unreliable in test context).
  """
  use ExUnit.Case, async: true

  describe "Mix.Tasks.PromoteAdmin" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Mix.Tasks.PromoteAdmin)
    end

    test "run/1 is exported" do
      assert {:run, 1} in Mix.Tasks.PromoteAdmin.__info__(:functions)
    end

    test "implements Mix.Task" do
      behaviours =
        Mix.Tasks.PromoteAdmin.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Mix.Task in behaviours
    end
  end

  describe "Mix.Tasks.Sfa.Touchosc.Generate" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Mix.Tasks.Sfa.Touchosc.Generate)
    end

    test "run/1 is exported" do
      assert {:run, 1} in Mix.Tasks.Sfa.Touchosc.Generate.__info__(:functions)
    end

    test "implements Mix.Task" do
      behaviours =
        Mix.Tasks.Sfa.Touchosc.Generate.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Mix.Task in behaviours
    end
  end

  describe "Mix.Tasks.BackfillAlbums" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Mix.Tasks.BackfillAlbums)
    end

    test "run/1 is exported" do
      assert {:run, 1} in Mix.Tasks.BackfillAlbums.__info__(:functions)
    end
  end

  describe "Mix.Tasks.FixDownloadPaths" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Mix.Tasks.FixDownloadPaths)
    end

    test "run/1 is exported" do
      assert {:run, 1} in Mix.Tasks.FixDownloadPaths.__info__(:functions)
    end
  end
end
