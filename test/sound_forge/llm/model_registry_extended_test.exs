defmodule SoundForge.LLM.ModelRegistryExtendedTest do
  @moduledoc """
  Extended tests for ModelRegistry: check_health, seeding completeness, edge cases.
  """
  use ExUnit.Case, async: false

  alias SoundForge.LLM.ModelRegistry

  describe "list_models/0 seeding completeness" do
    test "seeds all 12 known models" do
      models = ModelRegistry.list_models()
      assert length(models) >= 12
    end

    test "includes anthropic models" do
      models = ModelRegistry.list_models()
      anthropic = Enum.filter(models, &(&1.provider_type == :anthropic))
      assert length(anthropic) == 3
      names = Enum.map(anthropic, & &1.model) |> Enum.sort()
      assert "claude-haiku-4-5-20251001" in names
      assert "claude-opus-4-6" in names
      assert "claude-sonnet-4-20250514" in names
    end

    test "includes openai models" do
      models = ModelRegistry.list_models()
      openai = Enum.filter(models, &(&1.provider_type == :openai))
      assert length(openai) == 3
    end

    test "includes ollama models" do
      models = ModelRegistry.list_models()
      ollama = Enum.filter(models, &(&1.provider_type == :ollama))
      assert length(ollama) == 3
    end

    test "includes google gemini models" do
      models = ModelRegistry.list_models()
      gemini = Enum.filter(models, &(&1.provider_type == :google_gemini))
      assert length(gemini) == 2
    end

    test "includes azure openai model" do
      model = ModelRegistry.get_model(:azure_openai, "gpt-4o")
      assert model != nil
      assert model.provider_type == :azure_openai
    end

    test "all models have context_window" do
      for model <- ModelRegistry.list_models() do
        assert is_integer(model.context_window), "#{model.model} missing context_window"
        assert model.context_window > 0
      end
    end

    test "all models have cost field" do
      for model <- ModelRegistry.list_models() do
        assert model.cost in [:free, :low, :medium, :high], "#{model.model} bad cost"
      end
    end
  end

  describe "get_model/2 edge cases" do
    test "returns specific known models" do
      assert ModelRegistry.get_model(:openai, "gpt-4o") != nil
      assert ModelRegistry.get_model(:openai, "gpt-4o-mini") != nil
      assert ModelRegistry.get_model(:openai, "o3") != nil
      assert ModelRegistry.get_model(:ollama, "llama3.2") != nil
      assert ModelRegistry.get_model(:ollama, "mistral") != nil
      assert ModelRegistry.get_model(:ollama, "codellama") != nil
      assert ModelRegistry.get_model(:google_gemini, "gemini-2.0-flash") != nil
      assert ModelRegistry.get_model(:google_gemini, "gemini-2.5-pro") != nil
    end
  end

  describe "models_for_task/1 feature filtering" do
    test "audio feature filters to subset" do
      audio = ModelRegistry.models_for_task([:chat, :audio])
      assert length(audio) >= 1
      for m <- audio, do: assert(:audio in m.features)
    end

    test "json_mode models exist" do
      json = ModelRegistry.models_for_task([:json_mode])
      assert length(json) >= 3
    end

    test "tool_use models exist" do
      tu = ModelRegistry.models_for_task([:tool_use])
      assert length(tu) >= 5
    end

    test "empty feature list returns all models" do
      all = ModelRegistry.models_for_task([])
      assert length(all) == length(ModelRegistry.list_models())
    end
  end

  describe "best_model_for/2 preference edge cases" do
    test "speed preference with ollama provider filter" do
      result = ModelRegistry.best_model_for(:chat, prefer: :speed, provider_types: [:ollama])
      assert result != nil
      assert result.provider_type == :ollama
      assert result.speed == :fast
    end

    test "cost preference returns free ollama model" do
      result = ModelRegistry.best_model_for(:chat, prefer: :cost)
      assert result != nil
      assert result.cost == :free
    end

    test "quality preference with vision features" do
      result = ModelRegistry.best_model_for(:vision, prefer: :quality)
      assert result != nil
      assert :vision in result.features
      assert result.quality == :high
    end

    test "returns nil for impossible filter" do
      result = ModelRegistry.best_model_for(:chat,
        provider_types: [:nonexistent],
        features: [:chat]
      )
      assert result == nil
    end
  end

  describe "check_health/1" do
    test "accepts user_id and casts without error" do
      assert ModelRegistry.check_health(999) == :ok
    end
  end
end
