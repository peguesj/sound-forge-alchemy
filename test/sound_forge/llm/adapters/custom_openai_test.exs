defmodule SoundForge.LLM.Adapters.CustomOpenAITest do
  use ExUnit.Case, async: true

  alias SoundForge.LLM.Adapters.CustomOpenAI

  describe "chat/3" do
    test "returns request_failed for unreachable endpoint" do
      provider = %{
        api_key: nil,
        base_url: "http://127.0.0.1:1",
        default_model: "test-model"
      }

      result = CustomOpenAI.chat(provider, [%{role: "user", content: "test"}])
      assert {:error, {:request_failed, _}} = result
    end

    test "works without api_key (no auth header)" do
      provider = %{
        api_key: nil,
        base_url: "http://127.0.0.1:1",
        default_model: "test"
      }

      # Should still attempt the request (just no auth header)
      result = CustomOpenAI.chat(provider, [%{role: "user", content: "test"}])
      assert {:error, {:request_failed, _}} = result
    end
  end
end
