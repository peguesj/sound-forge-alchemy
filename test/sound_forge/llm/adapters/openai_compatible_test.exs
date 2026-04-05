defmodule SoundForge.LLM.Adapters.OpenAICompatibleTest do
  use ExUnit.Case, async: true

  alias SoundForge.LLM.Adapters.OpenAICompatible

  # We test the normalize_messages behavior by going through chat/1
  # with an unreachable URL (which will fail at HTTP level, testing
  # all logic up to the HTTP call)

  describe "chat/1 - request construction" do
    test "requires :url option" do
      assert_raise KeyError, ~r/url/, fn ->
        OpenAICompatible.chat(model: "test", messages: [])
      end
    end

    test "requires :model option" do
      assert_raise KeyError, ~r/model/, fn ->
        OpenAICompatible.chat(url: "http://invalid", messages: [])
      end
    end

    test "requires :messages option" do
      assert_raise KeyError, ~r/messages/, fn ->
        OpenAICompatible.chat(url: "http://invalid", model: "test")
      end
    end

    test "returns request_failed for unreachable endpoint" do
      result =
        OpenAICompatible.chat(
          url: "http://127.0.0.1:1/v1/chat/completions",
          model: "test",
          messages: [%{role: "user", content: "test"}]
        )

      assert {:error, {:request_failed, _}} = result
    end
  end
end
