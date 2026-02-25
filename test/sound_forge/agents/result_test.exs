defmodule SoundForge.Agents.ResultTest do
  use ExUnit.Case, async: true

  alias SoundForge.Agents.Result

  describe "ok/3" do
    test "builds a successful result with content" do
      result = Result.ok(MyAgent, "Great analysis!")
      assert result.agent == MyAgent
      assert result.content == "Great analysis!"
      assert result.success? == true
      assert result.error == nil
    end

    test "accepts data and usage opts" do
      result = Result.ok(MyAgent, "done", data: %{key: "C"}, usage: %{tokens: 100})
      assert result.data == %{key: "C"}
      assert result.usage == %{tokens: 100}
    end

    test "content can be nil" do
      result = Result.ok(MyAgent, nil)
      assert result.content == nil
      assert result.success? == true
    end
  end

  describe "error/2" do
    test "builds a failure result" do
      result = Result.error(MyAgent, "timeout")
      assert result.agent == MyAgent
      assert result.error == "timeout"
      assert result.success? == false
      assert result.content == nil
    end
  end

  describe "success?/1 and failure?/1" do
    test "success? returns true for ok result" do
      assert Result.success?(Result.ok(MyAgent, "ok"))
    end

    test "success? returns false for error result" do
      refute Result.success?(Result.error(MyAgent, "boom"))
    end

    test "failure? returns true for error result" do
      assert Result.failure?(Result.error(MyAgent, "boom"))
    end

    test "failure? returns false for ok result" do
      refute Result.failure?(Result.ok(MyAgent, "ok"))
    end
  end
end
