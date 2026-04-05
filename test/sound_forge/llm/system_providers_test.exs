defmodule SoundForge.LLM.Providers.SystemProvidersTest do
  @moduledoc """
  Tests for SystemProviders: env-based provider resolution.
  """
  use ExUnit.Case, async: true

  alias SoundForge.LLM.Providers.SystemProviders

  describe "list_system_providers/0" do
    test "returns a list" do
      providers = SystemProviders.list_system_providers()
      assert is_list(providers)
    end

    test "each provider has required fields" do
      for p <- SystemProviders.list_system_providers() do
        assert p.id == nil
        assert p.enabled == true
        assert is_atom(p.provider_type)
        assert is_binary(p.name)
        assert is_integer(p.priority)
        assert p.priority >= 1000
      end
    end

    test "ollama always available (has default base_url)" do
      providers = SystemProviders.list_system_providers()
      ollama = Enum.find(providers, &(&1.provider_type == :ollama))
      assert ollama != nil
      assert ollama.base_url == "http://localhost:11434"
    end

    test "system providers have config_json with system flag" do
      for p <- SystemProviders.list_system_providers() do
        assert p.config_json["system"] == true
      end
    end
  end

  describe "get_system_provider/1" do
    test "returns ollama provider" do
      p = SystemProviders.get_system_provider(:ollama)
      assert p != nil
      assert p.provider_type == :ollama
      assert p.default_model == "llama3.2"
    end

    test "returns nil for nonexistent provider type" do
      assert SystemProviders.get_system_provider(:nonexistent_xyz) == nil
    end
  end

  describe "any_available?/0" do
    test "returns true (ollama always has default)" do
      assert SystemProviders.any_available?()
    end
  end
end
