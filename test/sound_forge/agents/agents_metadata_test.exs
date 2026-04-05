defmodule SoundForge.Agents.AgentsMetadataTest do
  use ExUnit.Case, async: true

  @agents [
    SoundForge.Agents.CuePointAgent,
    SoundForge.Agents.LibraryAgent,
    SoundForge.Agents.MasteringAgent,
    SoundForge.Agents.MixPlanningAgent,
    SoundForge.Agents.StemIntelligenceAgent
  ]

  for agent <- @agents do
    describe "#{inspect(agent)}" do
      test "name/0 returns a string" do
        assert is_binary(unquote(agent).name())
        assert String.length(unquote(agent).name()) > 0
      end

      test "description/0 returns a string" do
        assert is_binary(unquote(agent).description())
      end

      test "capabilities/0 returns a list of atoms" do
        caps = unquote(agent).capabilities()
        assert is_list(caps)
        assert Enum.all?(caps, &is_atom/1)
        assert length(caps) > 0
      end

      test "preferred_traits/0 returns keyword list" do
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
