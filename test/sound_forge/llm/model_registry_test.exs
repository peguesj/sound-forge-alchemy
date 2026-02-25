defmodule SoundForge.LLM.ModelRegistryTest do
  use ExUnit.Case, async: false

  alias SoundForge.LLM.ModelRegistry

  # ModelRegistry is a named GenServer started in the application supervisor.
  # We test the public API that reads from the ETS table it populates.

  describe "list_models/0" do
    test "returns a non-empty list of model capability maps" do
      models = ModelRegistry.list_models()
      assert is_list(models)
      assert length(models) > 0
    end

    test "each model has required fields" do
      for model <- ModelRegistry.list_models() do
        assert Map.has_key?(model, :provider_type)
        assert Map.has_key?(model, :model)
        assert Map.has_key?(model, :features)
        assert Map.has_key?(model, :quality)
        assert Map.has_key?(model, :speed)
      end
    end
  end

  describe "get_model/2" do
    test "returns model map for known provider+model combination" do
      model = ModelRegistry.get_model(:anthropic, "claude-sonnet-4-20250514")
      assert model != nil
      assert model.provider_type == :anthropic
      assert :chat in model.features
    end

    test "returns nil for unknown model" do
      assert ModelRegistry.get_model(:anthropic, "nonexistent-model-9999") == nil
    end

    test "returns nil for unknown provider" do
      assert ModelRegistry.get_model(:unknown_provider, "gpt-4o") == nil
    end
  end

  describe "models_for_task/1" do
    test "returns models supporting :chat feature" do
      models = ModelRegistry.models_for_task([:chat])
      assert length(models) > 0
      Enum.each(models, fn m -> assert :chat in m.features end)
    end

    test "filters to models supporting :vision" do
      vision_models = ModelRegistry.models_for_task([:chat, :vision])
      assert length(vision_models) > 0
      Enum.each(vision_models, fn m ->
        assert :vision in m.features
      end)
    end

    test "returns empty list for unsupported feature combination" do
      models = ModelRegistry.models_for_task([:nonexistent_feature_xyz])
      assert models == []
    end
  end

  describe "best_model_for/2" do
    test "returns a model map when candidates exist" do
      result = ModelRegistry.best_model_for(:chat)
      assert result != nil
      assert Map.has_key?(result, :model)
    end

    test "prefers fast model when prefer: :speed" do
      result = ModelRegistry.best_model_for(:chat, prefer: :speed)
      assert result != nil
      assert result.speed == :fast
    end

    test "prefers high quality model when prefer: :quality" do
      result = ModelRegistry.best_model_for(:chat, prefer: :quality)
      assert result != nil
      assert result.quality == :high
    end

    test "returns nil when no candidates match provider_types filter" do
      result = ModelRegistry.best_model_for(:chat, provider_types: [:nonexistent_xyz])
      assert result == nil
    end
  end
end
