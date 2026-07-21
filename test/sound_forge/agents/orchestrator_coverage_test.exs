defmodule SoundForge.Agents.OrchestratorCoverageTest do
  @moduledoc "Tests for Agents.Orchestrator: select_agent, capability_map, auto-routing."
  use ExUnit.Case, async: true

  alias SoundForge.Agents.{Context, Orchestrator}

  describe "capability_map/0" do
    test "returns a non-empty keyword list of capabilities to modules" do
      map = Orchestrator.capability_map()
      assert is_list(map)
      assert length(map) > 10

      Enum.each(map, fn {cap, mod} ->
        assert is_atom(cap)
        assert is_atom(mod)
      end)
    end
  end

  describe "select_agent/2 with :task hint" do
    test "selects TrackAnalysisAgent for :track_analysis" do
      ctx = %Context{instruction: "anything", user_id: 1}

      assert Orchestrator.select_agent(ctx, task: :track_analysis) ==
               SoundForge.Agents.TrackAnalysisAgent
    end

    test "selects MixPlanningAgent for :mix_planning" do
      ctx = %Context{instruction: "anything", user_id: 1}

      assert Orchestrator.select_agent(ctx, task: :mix_planning) ==
               SoundForge.Agents.MixPlanningAgent
    end

    test "selects CuePointAgent for :cue_point_analysis" do
      ctx = %Context{instruction: "anything", user_id: 1}

      assert Orchestrator.select_agent(ctx, task: :cue_point_analysis) ==
               SoundForge.Agents.CuePointAgent
    end

    test "selects MasteringAgent for :mastering_advice" do
      ctx = %Context{instruction: "anything", user_id: 1}

      assert Orchestrator.select_agent(ctx, task: :mastering_advice) ==
               SoundForge.Agents.MasteringAgent
    end

    test "selects LibraryAgent for :library_search" do
      ctx = %Context{instruction: "anything", user_id: 1}

      assert Orchestrator.select_agent(ctx, task: :library_search) ==
               SoundForge.Agents.LibraryAgent
    end

    test "selects StemIntelligenceAgent for :stem_analysis" do
      ctx = %Context{instruction: "anything", user_id: 1}

      assert Orchestrator.select_agent(ctx, task: :stem_analysis) ==
               SoundForge.Agents.StemIntelligenceAgent
    end

    test "falls back to default for unknown task" do
      ctx = %Context{instruction: "anything", user_id: 1}

      assert Orchestrator.select_agent(ctx, task: :nonexistent_task) ==
               SoundForge.Agents.TrackAnalysisAgent
    end
  end

  describe "select_agent/2 with instruction auto-routing" do
    test "routes 'analyse the key' to TrackAnalysisAgent" do
      ctx = %Context{instruction: "Analyse the key and BPM", user_id: 1}
      assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.TrackAnalysisAgent
    end

    test "routes 'plan a mix set' to MixPlanningAgent" do
      ctx = %Context{instruction: "Plan a mix set with these tracks", user_id: 1}
      assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.MixPlanningAgent
    end

    test "routes 'isolate stems' to StemIntelligenceAgent" do
      ctx = %Context{instruction: "Isolate the vocal stem", user_id: 1}
      assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.StemIntelligenceAgent
    end

    test "routes 'mark cue points' to CuePointAgent" do
      ctx = %Context{instruction: "Mark cue points at the drop", user_id: 1}
      assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.CuePointAgent
    end

    test "routes 'master this track' to MasteringAgent" do
      ctx = %Context{instruction: "Master this track for loudness", user_id: 1}
      assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.MasteringAgent
    end

    test "routes 'find similar tracks' to LibraryAgent" do
      ctx = %Context{instruction: "Find similar tracks in my library", user_id: 1}
      assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.LibraryAgent
    end

    test "falls back to default for unrecognized instruction" do
      ctx = %Context{instruction: "do something undefined and magical", user_id: 1}
      assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.TrackAnalysisAgent
    end
  end
end
