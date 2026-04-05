defmodule SoundForge.LLM.Adapters.LiteLLMTest do
  use ExUnit.Case, async: true

  alias SoundForge.LLM.Adapters.LiteLLM

  describe "chat/3" do
    test "returns no_model_specified when model is nil" do
      provider = %{
        api_key: nil,
        base_url: "http://127.0.0.1:1",
        default_model: nil
      }

      result = LiteLLM.chat(provider, [%{role: "user", content: "test"}])
      assert {:error, :no_model_specified} = result
    end

    test "returns request_failed for unreachable endpoint with model" do
      provider = %{
        api_key: "test-key",
        base_url: "http://127.0.0.1:1",
        default_model: "anthropic/claude-sonnet-4-20250514"
      }

      result = LiteLLM.chat(provider, [%{role: "user", content: "test"}])
      assert {:error, {:request_failed, _}} = result
    end
  end
end
