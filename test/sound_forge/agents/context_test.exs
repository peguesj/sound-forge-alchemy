defmodule SoundForge.Agents.ContextTest do
  use ExUnit.Case, async: true

  alias SoundForge.Agents.{Context, Tool}

  describe "new/2" do
    test "creates a context with just an instruction" do
      ctx = Context.new("analyse the key")
      assert ctx.instruction == "analyse the key"
      assert ctx.messages == []
      assert ctx.user_id == nil
      assert ctx.track_id == nil
    end

    test "accepts optional keyword overrides" do
      ctx = Context.new("mix 5 tracks", user_id: "u1", track_id: "t2")
      assert ctx.user_id == "u1"
      assert ctx.track_id == "t2"
    end

    test "requires instruction" do
      assert_raise ArgumentError, fn ->
        struct!(Context, %{})
      end
    end
  end

  describe "append_message/2" do
    test "appends a message map to the messages list" do
      ctx = Context.new("test")
      msg = %{"role" => "user", "content" => "hello"}
      updated = Context.append_message(ctx, msg)
      assert updated.messages == [msg]
    end

    test "preserves order when appending multiple messages" do
      ctx = Context.new("test")
      m1 = %{"role" => "user", "content" => "first"}
      m2 = %{"role" => "assistant", "content" => "second"}
      ctx = Context.append_message(ctx, m1)
      ctx = Context.append_message(ctx, m2)
      assert ctx.messages == [m1, m2]
    end
  end

  describe "llm_tool_specs/1" do
    test "returns nil when tools is nil" do
      ctx = Context.new("test", tools: nil)
      assert Context.llm_tool_specs(ctx) == nil
    end

    test "returns nil when tools is empty list" do
      ctx = Context.new("test", tools: [])
      assert Context.llm_tool_specs(ctx) == nil
    end

    test "returns spec list when tools are present" do
      tool = %Tool{
        name: "search",
        description: "search tracks",
        params_schema: %{"type" => "object", "properties" => %{}},
        handler: fn _ -> {:ok, []} end
      }

      ctx = Context.new("test", tools: [tool])
      specs = Context.llm_tool_specs(ctx)
      assert is_list(specs)
      assert length(specs) == 1
    end
  end
end
