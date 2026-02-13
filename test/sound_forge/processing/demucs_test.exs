defmodule SoundForge.Processing.DemucsTest do
  use ExUnit.Case, async: true

  alias SoundForge.Processing.Demucs

  describe "list_models/0" do
    test "returns a list of models" do
      models = Demucs.list_models()
      assert is_list(models)
      assert length(models) > 0
    end

    test "each model has required keys" do
      for model <- Demucs.list_models() do
        assert Map.has_key?(model, :name)
        assert Map.has_key?(model, :description)
        assert Map.has_key?(model, :stems)
        assert is_binary(model.name)
        assert is_binary(model.description)
        assert is_integer(model.stems)
        assert model.stems > 0
      end
    end

    test "includes htdemucs default model" do
      models = Demucs.list_models()
      htdemucs = Enum.find(models, &(&1.name == "htdemucs"))
      assert htdemucs
      assert htdemucs.stems == 4
    end

    test "includes 6-stem model" do
      models = Demucs.list_models()
      six_stem = Enum.find(models, &(&1.stems == 6))
      assert six_stem
      assert six_stem.name == "htdemucs_6s"
    end
  end
end
