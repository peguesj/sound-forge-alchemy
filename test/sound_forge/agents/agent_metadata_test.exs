defmodule SoundForge.Agents.AgentMetadataTest do
  @moduledoc "Tests that all agent modules implement the Agent behaviour metadata correctly."
  use ExUnit.Case, async: true

  @agents [
    SoundForge.Agents.TrackAnalysisAgent,
    SoundForge.Agents.MixPlanningAgent,
    SoundForge.Agents.CuePointAgent,
    SoundForge.Agents.LibraryAgent,
    SoundForge.Agents.MasteringAgent,
    SoundForge.Agents.StemIntelligenceAgent
  ]

  for agent <- @agents do
    describe "#{inspect(agent)}" do
      test "name/0 returns a non-empty string" do
        name = unquote(agent).name()
        assert is_binary(name)
        assert name != ""
      end

      test "description/0 returns a non-empty string" do
        desc = unquote(agent).description()
        assert is_binary(desc)
        assert desc != ""
      end

      test "capabilities/0 returns a non-empty list of atoms" do
        caps = unquote(agent).capabilities()
        assert is_list(caps)
        assert length(caps) > 0
        Enum.each(caps, fn cap -> assert is_atom(cap) end)
      end

      test "preferred_traits/0 returns a keyword list" do
        traits = unquote(agent).preferred_traits()
        assert is_list(traits)
        assert Keyword.keyword?(traits)
      end

      test "system_prompt/0 returns a non-empty string" do
        prompt = unquote(agent).system_prompt()
        assert is_binary(prompt)
        assert String.length(prompt) > 10
      end
    end
  end
end
