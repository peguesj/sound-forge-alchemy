defmodule SoundForge.Agents.ContextExpandedTest do
  use ExUnit.Case, async: true

  alias SoundForge.Agents.Context
  alias SoundForge.Agents.Tool

  describe "new/2" do
    test "creates context with instruction" do
      ctx = Context.new("analyze this track")
      assert ctx.instruction == "analyze this track"
      assert ctx.messages == []
    end

    test "creates context with options" do
      ctx = Context.new("analyze", user_id: 42, track_id: "abc-123")
      assert ctx.user_id == 42
      assert ctx.track_id == "abc-123"
    end

    test "raises on non-binary instruction" do
      assert_raise FunctionClauseError, fn ->
        Context.new(42)
      end
    end
  end

  describe "append_message/2" do
    test "appends a message to the messages list" do
      ctx = Context.new("test")
      msg = %{role: "user", content: "hello"}
      updated = Context.append_message(ctx, msg)
      assert length(updated.messages) == 1
      assert hd(updated.messages) == msg
    end

    test "preserves message order" do
      ctx =
        Context.new("test")
        |> Context.append_message(%{role: "user", content: "first"})
        |> Context.append_message(%{role: "assistant", content: "second"})

      assert length(ctx.messages) == 2
      assert Enum.at(ctx.messages, 0).content == "first"
      assert Enum.at(ctx.messages, 1).content == "second"
    end
  end

  describe "llm_tool_specs/1" do
    test "returns nil when tools is nil" do
      ctx = Context.new("test")
      assert Context.llm_tool_specs(ctx) == nil
    end

    test "returns nil when tools is empty list" do
      ctx = Context.new("test", tools: [])
      assert Context.llm_tool_specs(ctx) == nil
    end

    test "returns formatted specs when tools present" do
      tool = %Tool{
        name: "test_tool",
        description: "A test",
        params_schema: %{"type" => "object"},
        handler: fn _ -> {:ok, "done"} end
      }

      ctx = Context.new("test", tools: [tool])
      specs = Context.llm_tool_specs(ctx)

      assert length(specs) == 1
      assert hd(specs)["function"]["name"] == "test_tool"
    end
  end
end
