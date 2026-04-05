defmodule SoundForge.LLM.Adapters.GoogleGeminiCoverageTest do
  @moduledoc "Tests for GoogleGemini adapter: chat without API key."
  use ExUnit.Case, async: true

  alias SoundForge.LLM.Adapters.GoogleGemini

  describe "chat/3" do
    test "returns error when api_key is nil" do
      provider = %{api_key: nil, default_model: "gemini-2.0-flash"}
      messages = [%{role: "user", content: "Hello"}]
      assert {:error, :missing_api_key} = GoogleGemini.chat(provider, messages)
    end

    test "returns error when api_key is false" do
      provider = %{api_key: false, default_model: "gemini-2.0-flash"}
      messages = [%{role: "user", content: "Hello"}]
      assert {:error, :missing_api_key} = GoogleGemini.chat(provider, messages)
    end
  end
end
