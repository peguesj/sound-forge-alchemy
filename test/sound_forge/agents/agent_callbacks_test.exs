defmodule SoundForge.Agents.AgentCallbacksTest do
  @moduledoc """
  Tests pure callback functions (name, description, capabilities, preferred_traits,
  system_prompt) for all LLM agent modules. These are pure functions that don't
  require LLM services.
  """
  use ExUnit.Case, async: true

  @agents [
    SoundForge.Agents.CuePointAgent,
    SoundForge.Agents.LibraryAgent,
    SoundForge.Agents.MasteringAgent,
    SoundForge.Agents.StemIntelligenceAgent,
    SoundForge.Agents.MixPlanningAgent,
    SoundForge.Agents.TrackAnalysisAgent
  ]

  describe "all agents implement callbacks" do
    for agent <- @agents do
      agent_name = agent |> Module.split() |> List.last()

      test "#{agent_name} has name/0 returning a string" do
        assert is_binary(unquote(agent).name())
        assert unquote(agent).name() != ""
      end

      test "#{agent_name} has description/0 returning a string" do
        assert is_binary(unquote(agent).description())
        assert unquote(agent).description() != ""
      end

      test "#{agent_name} has capabilities/0 returning a non-empty list" do
        caps = unquote(agent).capabilities()
        assert is_list(caps)
        assert length(caps) > 0
        assert Enum.all?(caps, &is_atom/1)
      end

      test "#{agent_name} has preferred_traits/0 returning a keyword list" do
        traits = unquote(agent).preferred_traits()
        assert is_list(traits)
        assert Keyword.keyword?(traits)
      end

      test "#{agent_name} has system_prompt/0 returning a non-empty string" do
        prompt = unquote(agent).system_prompt()
        assert is_binary(prompt)
        assert String.length(prompt) > 20
      end
    end
  end

  describe "CuePointAgent specific" do
    test "name is cue_point_agent" do
      assert SoundForge.Agents.CuePointAgent.name() == "cue_point_agent"
    end

    test "capabilities include cue_point_analysis" do
      assert :cue_point_analysis in SoundForge.Agents.CuePointAgent.capabilities()
    end
  end

  describe "LibraryAgent specific" do
    test "name is library_agent" do
      assert SoundForge.Agents.LibraryAgent.name() == "library_agent"
    end

    test "capabilities include library_search" do
      assert :library_search in SoundForge.Agents.LibraryAgent.capabilities()
    end
  end

  describe "MasteringAgent specific" do
    test "name is mastering_agent" do
      assert SoundForge.Agents.MasteringAgent.name() == "mastering_agent"
    end

    test "capabilities include mastering_advice" do
      assert :mastering_advice in SoundForge.Agents.MasteringAgent.capabilities()
    end
  end

  describe "StemIntelligenceAgent specific" do
    test "name is stem_intelligence_agent" do
      assert SoundForge.Agents.StemIntelligenceAgent.name() == "stem_intelligence_agent"
    end

    test "capabilities include stem_analysis" do
      assert :stem_analysis in SoundForge.Agents.StemIntelligenceAgent.capabilities()
    end
  end

  describe "MixPlanningAgent specific" do
    test "name is mix_planning_agent" do
      assert SoundForge.Agents.MixPlanningAgent.name() == "mix_planning_agent"
    end

    test "capabilities include mix_planning" do
      assert :mix_planning in SoundForge.Agents.MixPlanningAgent.capabilities()
    end

    test "system_prompt includes Camelot wheel knowledge" do
      prompt = SoundForge.Agents.MixPlanningAgent.system_prompt()
      assert prompt =~ "Camelot" or prompt =~ "mix" or prompt =~ "transition"
    end
  end

  describe "TrackAnalysisAgent specific" do
    test "name is track_analysis_agent" do
      assert SoundForge.Agents.TrackAnalysisAgent.name() == "track_analysis_agent"
    end
  end
end
