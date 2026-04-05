defmodule SoundForge.LLM.Adapters.OpenAITest do
  use ExUnit.Case, async: true

  alias SoundForge.LLM.Adapters.OpenAI

  describe "chat/3" do
    test "returns request_failed for unreachable endpoint" do
      provider = %{
        api_key: "sk-test",
        base_url: "http://127.0.0.1:1",
        default_model: "gpt-4o"
      }

      result = OpenAI.chat(provider, [%{role: "user", content: "test"}])
      assert {:error, {:request_failed, _}} = result
    end
  end
end
