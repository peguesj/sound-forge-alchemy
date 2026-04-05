defmodule SoundForge.AgentsTest do
  @moduledoc """
  Tests for the Agents framework: Agent behaviour implementations,
  Orchestrator, Context, and Tool structs.
  """
  use ExUnit.Case, async: true

  alias SoundForge.Agents.{Context, Result, Tool}

  describe "Agent implementations" do
    test "CuePointAgent implements name/0" do
      assert SoundForge.Agents.CuePointAgent.name() == "cue_point_agent"
    end

    test "CuePointAgent implements description/0" do
      assert is_binary(SoundForge.Agents.CuePointAgent.description())
    end

    test "CuePointAgent implements capabilities/0" do
      caps = SoundForge.Agents.CuePointAgent.capabilities()
      assert is_list(caps)
    end

    test "CuePointAgent implements preferred_traits/0" do
      traits = SoundForge.Agents.CuePointAgent.preferred_traits()
      assert is_list(traits)
    end

    test "CuePointAgent implements system_prompt/0" do
      prompt = SoundForge.Agents.CuePointAgent.system_prompt()
      assert is_binary(prompt)
    end

    test "MixPlanningAgent implements name/0" do
      assert SoundForge.Agents.MixPlanningAgent.name() == "mix_planning_agent"
    end

    test "MixPlanningAgent implements description/0" do
      assert is_binary(SoundForge.Agents.MixPlanningAgent.description())
    end

    test "MixPlanningAgent implements capabilities/0" do
      caps = SoundForge.Agents.MixPlanningAgent.capabilities()
      assert is_list(caps)
    end

    test "MixPlanningAgent implements preferred_traits/0" do
      traits = SoundForge.Agents.MixPlanningAgent.preferred_traits()
      assert is_list(traits)
    end

    test "MixPlanningAgent implements system_prompt/0" do
      prompt = SoundForge.Agents.MixPlanningAgent.system_prompt()
      assert is_binary(prompt)
    end
  end

  describe "Orchestrator" do
    test "capability_map returns a list" do
      map = SoundForge.Agents.Orchestrator.capability_map()
      assert is_list(map)
      assert length(map) > 0
    end

    test "capability_map contains mix_planning" do
      map = SoundForge.Agents.Orchestrator.capability_map()
      assert Keyword.has_key?(map, :mix_planning)
    end

    test "capability_map contains cue_point_analysis" do
      map = SoundForge.Agents.Orchestrator.capability_map()
      assert Keyword.has_key?(map, :cue_point_analysis)
    end

    test "capability_map contains track_analysis" do
      map = SoundForge.Agents.Orchestrator.capability_map()
      assert Keyword.has_key?(map, :track_analysis)
    end
  end

  describe "StemIntelligenceAgent" do
    test "implements name/0" do
      assert SoundForge.Agents.StemIntelligenceAgent.name() == "stem_intelligence_agent"
    end

    test "implements description/0" do
      assert is_binary(SoundForge.Agents.StemIntelligenceAgent.description())
    end

    test "implements capabilities/0" do
      caps = SoundForge.Agents.StemIntelligenceAgent.capabilities()
      assert is_list(caps)
      assert length(caps) > 0
    end

    test "implements preferred_traits/0" do
      traits = SoundForge.Agents.StemIntelligenceAgent.preferred_traits()
      assert is_list(traits)
    end

    test "implements system_prompt/0" do
      prompt = SoundForge.Agents.StemIntelligenceAgent.system_prompt()
      assert is_binary(prompt)
      assert String.length(prompt) > 10
    end
  end

  describe "LibraryAgent" do
    test "implements name/0" do
      assert SoundForge.Agents.LibraryAgent.name() == "library_agent"
    end

    test "implements description/0" do
      assert is_binary(SoundForge.Agents.LibraryAgent.description())
    end

    test "implements capabilities/0" do
      caps = SoundForge.Agents.LibraryAgent.capabilities()
      assert is_list(caps)
    end

    test "implements preferred_traits/0" do
      traits = SoundForge.Agents.LibraryAgent.preferred_traits()
      assert is_list(traits)
    end

    test "implements system_prompt/0" do
      prompt = SoundForge.Agents.LibraryAgent.system_prompt()
      assert is_binary(prompt)
    end
  end

  describe "MasteringAgent" do
    test "implements name/0" do
      assert SoundForge.Agents.MasteringAgent.name() == "mastering_agent"
    end

    test "implements description/0" do
      assert is_binary(SoundForge.Agents.MasteringAgent.description())
    end

    test "implements capabilities/0" do
      caps = SoundForge.Agents.MasteringAgent.capabilities()
      assert is_list(caps)
    end

    test "implements preferred_traits/0" do
      traits = SoundForge.Agents.MasteringAgent.preferred_traits()
      assert is_list(traits)
    end

    test "implements system_prompt/0" do
      prompt = SoundForge.Agents.MasteringAgent.system_prompt()
      assert is_binary(prompt)
    end
  end

  describe "TrackAnalysisAgent" do
    test "implements name/0" do
      assert SoundForge.Agents.TrackAnalysisAgent.name() == "track_analysis_agent"
    end

    test "implements description/0" do
      assert is_binary(SoundForge.Agents.TrackAnalysisAgent.description())
    end

    test "implements capabilities/0" do
      caps = SoundForge.Agents.TrackAnalysisAgent.capabilities()
      assert is_list(caps)
    end
  end

  describe "Context struct" do
    test "creates context with fields" do
      ctx = %Context{instruction: "test instruction", user_id: 1}
      assert ctx.instruction == "test instruction"
      assert ctx.user_id == 1
    end

    test "context has default values" do
      ctx = %Context{instruction: "test"}
      assert ctx.messages == []
      assert ctx.data == nil
    end

    test "context with track_id" do
      ctx = %Context{instruction: "analyze", track_id: "abc-123"}
      assert ctx.track_id == "abc-123"
    end

    test "context with track_ids list" do
      ctx = %Context{instruction: "batch", track_ids: ["a", "b", "c"]}
      assert length(ctx.track_ids) == 3
    end
  end

  describe "Result struct" do
    test "creates result with required fields" do
      result = %Result{agent: "test_agent", content: "hello"}
      assert result.agent == "test_agent"
      assert result.content == "hello"
    end

    test "result defaults success to true" do
      result = %Result{agent: "test", content: "ok"}
      assert result.success? == true
    end

    test "result with error" do
      result = %Result{agent: "test", content: nil, error: "failed", success?: false}
      assert result.success? == false
      assert result.error == "failed"
    end
  end

  describe "Tool struct" do
    test "creates tool with required fields" do
      handler = fn _params -> {:ok, nil} end
      tool = %Tool{name: "search", description: "search tool", params_schema: %{}, handler: handler}
      assert tool.name == "search"
      assert tool.description == "search tool"
    end

    test "tool with handler" do
      handler = fn _params -> {:ok, "result"} end
      tool = %Tool{name: "test", description: "test", params_schema: %{}, handler: handler}
      assert {:ok, "result"} = tool.handler.(%{})
    end
  end
end
