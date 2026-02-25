defmodule SoundForge.Agents.OrchestratorTest do
  use SoundForge.DataCase, async: true

  import SoundForge.AccountsFixtures
  alias SoundForge.Agents.{Context, Orchestrator}

  # ---------------------------------------------------------------------------
  # select_agent/2
  # ---------------------------------------------------------------------------

  describe "select_agent/2 — task hint dispatch" do
    test "routes :track_analysis to TrackAnalysisAgent" do
      ctx = Context.new("analyse")
      assert Orchestrator.select_agent(ctx, task: :track_analysis) ==
               SoundForge.Agents.TrackAnalysisAgent
    end

    test "routes :mix_planning to MixPlanningAgent" do
      ctx = Context.new("mix")
      assert Orchestrator.select_agent(ctx, task: :mix_planning) ==
               SoundForge.Agents.MixPlanningAgent
    end

    test "routes :stem_analysis to StemIntelligenceAgent" do
      ctx = Context.new("stems")
      assert Orchestrator.select_agent(ctx, task: :stem_analysis) ==
               SoundForge.Agents.StemIntelligenceAgent
    end

    test "routes :mastering_advice to MasteringAgent" do
      ctx = Context.new("master")
      assert Orchestrator.select_agent(ctx, task: :mastering_advice) ==
               SoundForge.Agents.MasteringAgent
    end

    test "routes :library_search to LibraryAgent" do
      ctx = Context.new("find")
      assert Orchestrator.select_agent(ctx, task: :library_search) ==
               SoundForge.Agents.LibraryAgent
    end

    test "falls back to default for unknown task" do
      ctx = Context.new("unknown")
      assert Orchestrator.select_agent(ctx, task: :nonexistent_task) ==
               SoundForge.Agents.TrackAnalysisAgent
    end
  end

  describe "select_agent/2 — instruction-based auto-routing" do
    test "routes key/BPM questions to TrackAnalysisAgent" do
      for word <- ["key", "bpm", "tempo", "chord", "harmonic"] do
        ctx = Context.new("What is the #{word} of this track?")
        assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.TrackAnalysisAgent,
               "expected TrackAnalysisAgent for word: #{word}"
      end
    end

    test "routes mix/playlist instructions to MixPlanningAgent" do
      for word <- ["mix", "playlist", "sequence", "transition"] do
        ctx = Context.new("#{word} these tracks together")
        assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.MixPlanningAgent,
               "expected MixPlanningAgent for word: #{word}"
      end
    end

    test "routes stem/vocal instructions to StemIntelligenceAgent" do
      for word <- ["stem", "vocal", "drum", "bass"] do
        ctx = Context.new("isolate the #{word}")
        assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.StemIntelligenceAgent,
               "expected StemIntelligenceAgent for word: #{word}"
      end
    end

    test "routes mastering/loudness to MasteringAgent" do
      for word <- ["master", "loud", "lufs", "dynamic"] do
        ctx = Context.new("check #{word} levels")
        assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.MasteringAgent,
               "expected MasteringAgent for word: #{word}"
      end
    end

    test "falls back to TrackAnalysisAgent when no pattern matches" do
      ctx = Context.new("hello world")
      assert Orchestrator.select_agent(ctx, []) == SoundForge.Agents.TrackAnalysisAgent
    end
  end

  describe "capability_map/0" do
    test "returns a list of {atom, module} tuples" do
      map = Orchestrator.capability_map()
      assert is_list(map)
      assert length(map) > 0
      Enum.each(map, fn {cap, mod} ->
        assert is_atom(cap)
        assert is_atom(mod)
      end)
    end

    test "contains expected capability atoms" do
      caps = Orchestrator.capability_map() |> Enum.map(&elem(&1, 0))
      assert :track_analysis in caps
      assert :mix_planning in caps
      assert :mastering_advice in caps
    end
  end

  describe "pipeline/3" do
    test "returns a tagged tuple result for a single-agent pipeline" do
      user = user_fixture()
      # No LLM providers configured, so the agent fails gracefully
      ctx = Context.new("pipeline test", user_id: user.id)
      result = Orchestrator.pipeline(ctx, [SoundForge.Agents.TrackAnalysisAgent])
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts empty agent list and returns ok with empty results" do
      ctx = Context.new("empty pipeline")
      assert {:ok, []} = Orchestrator.pipeline(ctx, [])
    end
  end
end
