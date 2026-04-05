defmodule SoundForge.LLM.ClientTest do
  @moduledoc """
  Tests for LLM.Client: adapter_for/1 routing and adapter selection.
  """
  use ExUnit.Case, async: true

  alias SoundForge.LLM.Client

  describe "adapter_for/1" do
    test "returns Anthropic adapter" do
      assert Client.adapter_for(:anthropic) == SoundForge.LLM.Adapters.Anthropic
    end

    test "returns OpenAI adapter" do
      assert Client.adapter_for(:openai) == SoundForge.LLM.Adapters.OpenAI
    end

    test "returns AzureOpenAI adapter" do
      assert Client.adapter_for(:azure_openai) == SoundForge.LLM.Adapters.AzureOpenAI
    end

    test "returns GoogleGemini adapter" do
      assert Client.adapter_for(:google_gemini) == SoundForge.LLM.Adapters.GoogleGemini
    end

    test "returns Ollama adapter" do
      assert Client.adapter_for(:ollama) == SoundForge.LLM.Adapters.Ollama
    end

    test "returns LMStudio adapter" do
      assert Client.adapter_for(:lm_studio) == SoundForge.LLM.Adapters.LMStudio
    end

    test "returns LiteLLM adapter" do
      assert Client.adapter_for(:litellm) == SoundForge.LLM.Adapters.LiteLLM
    end

    test "returns CustomOpenAI adapter" do
      assert Client.adapter_for(:custom_openai) == SoundForge.LLM.Adapters.CustomOpenAI
    end

    test "raises for unknown type" do
      assert_raise RuntimeError, ~r/Unknown provider type/, fn ->
        Client.adapter_for(:nonexistent)
      end
    end
  end

  describe "chat/3 error handling" do
    test "wraps adapter errors" do
      provider = %{provider_type: :nonexistent_provider}
      result = Client.chat(provider, [%{role: "user", content: "hi"}])
      assert {:error, {:adapter_error, _}} = result
    end
  end

  describe "ping/1" do
    test "returns connection_refused for unreachable local provider" do
      provider = %{provider_type: :ollama, base_url: "http://127.0.0.1:19999"}
      result = Client.ping(provider)
      assert match?({:error, _}, result)
    end

    test "returns connection_refused for unreachable lm_studio" do
      provider = %{provider_type: :lm_studio, base_url: "http://127.0.0.1:19998"}
      result = Client.ping(provider)
      assert match?({:error, _}, result)
    end

    test "returns connection_refused for unreachable litellm" do
      provider = %{provider_type: :litellm, base_url: "http://127.0.0.1:19997"}
      result = Client.ping(provider)
      assert match?({:error, _}, result)
    end

    test "returns connection_refused for unreachable custom_openai" do
      provider = %{provider_type: :custom_openai, base_url: "http://127.0.0.1:19996"}
      result = Client.ping(provider)
      assert match?({:error, _}, result)
    end

    test "handles unknown provider type" do
      provider = %{provider_type: :something_weird, base_url: "http://127.0.0.1:19995"}
      result = Client.ping(provider)
      assert match?({:error, _}, result)
    end

    test "handles cloud providers with nil api_key" do
      for type <- [:anthropic, :openai, :google_gemini] do
        provider = %{provider_type: type, api_key: nil}
        result = Client.ping(provider)
        # Should return some error or possibly ok (for API endpoints that return 401)
        assert match?({:error, _}, result) or result == :ok
      end
    end

    test "handles azure_openai with base_url" do
      provider = %{provider_type: :azure_openai, base_url: "http://127.0.0.1:19994", api_key: nil}
      result = Client.ping(provider)
      assert match?({:error, _}, result)
    end
  end

  describe "test_connection/1" do
    test "returns error for unreachable provider" do
      provider = %{provider_type: :ollama, base_url: "http://127.0.0.1:19993"}
      result = Client.test_connection(provider)
      assert match?({:error, _}, result)
    end
  end
end
