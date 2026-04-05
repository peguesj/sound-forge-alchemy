defmodule SoundForge.Agents.ResultExpandedTest do
  use ExUnit.Case, async: true

  alias SoundForge.Agents.Result

  describe "ok/3" do
    test "creates successful result with content" do
      result = Result.ok(MyAgent, "analysis complete")
      assert result.agent == MyAgent
      assert result.content == "analysis complete"
      assert result.success?
      assert result.error == nil
    end

    test "creates result with data and usage" do
      result = Result.ok(MyAgent, "done", data: %{bpm: 128}, usage: %{tokens: 150})
      assert result.data == %{bpm: 128}
      assert result.usage == %{tokens: 150}
    end

    test "creates result with nil content" do
      result = Result.ok(MyAgent, nil)
      assert result.content == nil
      assert result.success?
    end
  end

  describe "error/2" do
    test "creates failure result" do
      result = Result.error(MyAgent, "LLM timeout")
      assert result.agent == MyAgent
      assert result.error == "LLM timeout"
      refute result.success?
    end

    test "stores arbitrary error terms" do
      result = Result.error(MyAgent, {:rate_limited, 429})
      assert result.error == {:rate_limited, 429}
    end
  end

  describe "success?/1" do
    test "returns true for ok results" do
      result = Result.ok(MyAgent, "done")
      assert Result.success?(result)
    end

    test "returns false for error results" do
      result = Result.error(MyAgent, "fail")
      refute Result.success?(result)
    end
  end

  describe "failure?/1" do
    test "returns true for error results" do
      result = Result.error(MyAgent, "fail")
      assert Result.failure?(result)
    end

    test "returns false for ok results" do
      result = Result.ok(MyAgent, "done")
      refute Result.failure?(result)
    end
  end
end
