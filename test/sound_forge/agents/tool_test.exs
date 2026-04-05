defmodule SoundForge.Agents.ToolTest do
  @moduledoc "Tests for Agent Tool struct, call, and serialization."
  use ExUnit.Case, async: true

  alias SoundForge.Agents.Tool

  defp sample_tool do
    %Tool{
      name: "get_data",
      description: "Fetches data by ID",
      params_schema: %{
        "type" => "object",
        "properties" => %{"id" => %{"type" => "string"}},
        "required" => ["id"]
      },
      handler: fn %{"id" => id} -> {:ok, %{id: id, value: "found"}} end
    }
  end

  describe "call/2" do
    test "invokes handler and returns result" do
      assert {:ok, %{id: "abc", value: "found"}} = Tool.call(sample_tool(), %{"id" => "abc"})
    end

    test "returns error tuple on handler exception" do
      error_tool = %Tool{
        name: "fail",
        description: "Always fails",
        params_schema: %{},
        handler: fn _params -> raise "boom" end
      }

      assert {:error, "boom"} = Tool.call(error_tool, %{})
    end
  end

  describe "to_llm_spec/1" do
    test "serializes to OpenAI function-calling format" do
      tool = sample_tool()
      spec = Tool.to_llm_spec(tool)
      assert spec["type"] == "function"
      assert spec["function"]["name"] == "get_data"
      assert spec["function"]["description"] == "Fetches data by ID"
      assert spec["function"]["parameters"] == tool.params_schema
    end
  end
end
