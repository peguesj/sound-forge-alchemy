defmodule SoundForge.Agents.AgentsCoverageTest do
  @moduledoc "Tests for all agent modules: name, description, capabilities, preferred_traits, system_prompt."
  use ExUnit.Case, async: true

  alias SoundForge.Agents.{
    CuePointAgent,
    LibraryAgent,
    MasteringAgent,
    MixPlanningAgent,
    StemIntelligenceAgent,
    TrackAnalysisAgent
  }

  @agents [
    CuePointAgent,
    LibraryAgent,
    MasteringAgent,
    MixPlanningAgent,
    StemIntelligenceAgent,
    TrackAnalysisAgent
  ]

  describe "agent interface compliance" do
    for agent <- @agents do
      mod_name = agent |> Module.split() |> List.last()

      test "#{mod_name}.name/0 returns a string" do
        assert is_binary(unquote(agent).name())
      end

      test "#{mod_name}.description/0 returns a string" do
        assert is_binary(unquote(agent).description())
      end

      test "#{mod_name}.capabilities/0 returns a non-empty list of atoms" do
        caps = unquote(agent).capabilities()
        assert is_list(caps)
        assert length(caps) > 0
        Enum.each(caps, fn c -> assert is_atom(c) end)
      end

      test "#{mod_name}.preferred_traits/0 returns a keyword list" do
        traits = unquote(agent).preferred_traits()
        assert is_list(traits)
        Enum.each(traits, fn {k, v} ->
          assert is_atom(k)
          assert is_atom(v)
        end)
      end

      test "#{mod_name}.system_prompt/0 returns a non-empty string" do
        prompt = unquote(agent).system_prompt()
        assert is_binary(prompt)
        assert String.length(prompt) > 50
      end
    end
  end
end
