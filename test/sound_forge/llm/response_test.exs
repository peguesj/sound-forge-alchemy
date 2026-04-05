defmodule SoundForge.LLM.ResponseTest do
  use ExUnit.Case, async: true

  alias SoundForge.LLM.Response

  describe "struct" do
    test "creates with all fields" do
      resp = %Response{
        content: "Hello!",
        model: "claude-3-opus-20240229",
        usage: %{input_tokens: 10, output_tokens: 5},
        finish_reason: "stop",
        raw_response: %{"id" => "msg_abc"}
      }

      assert resp.content == "Hello!"
      assert resp.model == "claude-3-opus-20240229"
      assert resp.finish_reason == "stop"
    end

    test "defaults usage to empty map" do
      resp = %Response{}
      assert resp.usage == %{}
    end

    test "defaults raw_response to empty map" do
      resp = %Response{}
      assert resp.raw_response == %{}
    end

    test "content defaults to nil" do
      resp = %Response{}
      assert resp.content == nil
    end
  end
end
