defmodule SoundForge.Agents.AgentsTest do
  @moduledoc """
  Tests for all specialist agent modules — pure function coverage
  (name, description, capabilities, preferred_traits, system_prompt, format_messages).
  """
  use ExUnit.Case, async: true

  alias SoundForge.Agents.{
    CuePointAgent,
    LibraryAgent,
    MasteringAgent,
    MixPlanningAgent,
    StemIntelligenceAgent
  }

  @agents [
    {CuePointAgent, "cue_point_agent",
     [:cue_point_analysis, :loop_region_detection, :drop_detection, :phrase_boundary_detection]},
    {LibraryAgent, "library_agent",
     [
       :library_search,
       :track_recommendations,
       :playlist_curation,
       :genre_classification,
       :mood_tagging
     ]},
    {MasteringAgent, "mastering_agent",
     [
       :mastering_advice,
       :loudness_analysis,
       :dynamic_range_advice,
       :eq_recommendations,
       :compression_advice
     ]},
    {MixPlanningAgent, "mix_planning_agent",
     [:mix_planning, :track_sequencing, :transition_advice, :energy_flow, :key_compatibility]},
    {StemIntelligenceAgent, "stem_intelligence_agent",
     [:stem_analysis, :stem_quality_assessment, :stem_recommendations, :loop_extraction_advice]}
  ]

  for {mod, expected_name, expected_caps} <- @agents do
    mod_name = mod |> Module.split() |> List.last()

    describe "#{mod_name}" do
      test "name/0 returns expected name" do
        assert unquote(mod).name() == unquote(expected_name)
      end

      test "description/0 returns a non-empty string" do
        desc = unquote(mod).description()
        assert is_binary(desc)
        assert String.length(desc) > 10
      end

      test "capabilities/0 returns expected atoms" do
        assert unquote(mod).capabilities() == unquote(expected_caps)
      end

      test "preferred_traits/0 returns a keyword list with :task and :speed" do
        traits = unquote(mod).preferred_traits()
        assert is_list(traits)
        assert Keyword.has_key?(traits, :task)
        assert Keyword.has_key?(traits, :speed)
      end

      test "system_prompt/0 returns a non-empty string" do
        prompt = unquote(mod).system_prompt()
        assert is_binary(prompt)
        assert String.length(prompt) > 50
      end

      test "format_messages/2 with nil prepends system prompt" do
        msgs = unquote(mod).format_messages(nil, [%{"role" => "user", "content" => "hello"}])
        assert length(msgs) == 2
        assert hd(msgs)["role"] == "system"
        assert List.last(msgs)["content"] == "hello"
      end

      test "format_messages/2 with :none omits system prompt" do
        msgs = unquote(mod).format_messages(:none, [%{"role" => "user", "content" => "hello"}])
        assert length(msgs) == 1
        assert hd(msgs)["role"] == "user"
      end

      test "format_messages/2 with custom string uses it as system" do
        msgs =
          unquote(mod).format_messages("custom sys", [%{"role" => "user", "content" => "hi"}])

        assert length(msgs) == 2
        assert hd(msgs)["content"] == "custom sys"
      end

      test "module is loaded" do
        assert Code.ensure_loaded?(unquote(mod))
      end

      test "implements Agent behaviour" do
        behaviours =
          unquote(mod).__info__(:attributes)
          |> Keyword.get_values(:behaviour)
          |> List.flatten()

        assert SoundForge.Agents.Agent in behaviours
      end
    end
  end
end
