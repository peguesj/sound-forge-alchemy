defmodule SoundForge.LLM.Adapters.AnthropicTest do
  use ExUnit.Case, async: true

  alias SoundForge.LLM.Adapters.Anthropic

  describe "chat/3" do
    test "returns missing_api_key when api_key is nil" do
      provider = %{api_key: nil, base_url: nil, default_model: nil}
      assert {:error, :missing_api_key} = Anthropic.chat(provider, [])
    end

    test "returns request_failed for unreachable endpoint" do
      provider = %{
        api_key: "sk-test",
        base_url: "http://127.0.0.1:1",
        default_model: "claude-sonnet-4-20250514"
      }

      result = Anthropic.chat(provider, [%{role: "user", content: "test"}])
      assert {:error, {:request_failed, _}} = result
    end
  end
end
