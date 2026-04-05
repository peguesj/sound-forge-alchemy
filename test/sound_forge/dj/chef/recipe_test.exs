defmodule SoundForge.DJ.Chef.RecipeTest do
  use ExUnit.Case, async: true

  alias SoundForge.DJ.Chef.Recipe

  describe "struct" do
    test "can create a recipe with all required fields" do
      recipe = %Recipe{
        prompt: "deep house set",
        parsed_intent: %{genre: "deep house", bpm_range: [120, 125]},
        tracks: [
          %{
            track_id: "abc",
            title: "Track 1",
            artist: "DJ Test",
            tempo: 122.0,
            key: "Am",
            energy: 0.7,
            compatibility_score: 0.95
          }
        ],
        deck_assignments: [%{deck: 1, track_id: "abc", order: 0}],
        mixing_notes: "Smooth transitions recommended",
        generated_at: DateTime.utc_now()
      }

      assert recipe.prompt == "deep house set"
      assert length(recipe.tracks) == 1
      assert is_nil(recipe.cue_plan)
      assert is_nil(recipe.stems_to_load)
    end

    test "struct!/2 raises when missing required fields" do
      assert_raise ArgumentError, fn ->
        struct!(Recipe, %{prompt: "test"})
      end
    end

    test "accepts optional cue_plan and stems_to_load" do
      recipe = %Recipe{
        prompt: "test",
        parsed_intent: %{},
        tracks: [],
        deck_assignments: [],
        mixing_notes: "None",
        generated_at: DateTime.utc_now(),
        cue_plan: [%{track_id: "x", cue_type: :hot, position_ms: 0, label: "Drop"}],
        stems_to_load: [%{track_id: "x", stem_type: :vocals, action: :load}]
      }

      assert length(recipe.cue_plan) == 1
      assert length(recipe.stems_to_load) == 1
    end
  end
end
