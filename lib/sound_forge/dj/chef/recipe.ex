defmodule SoundForge.DJ.Chef.Recipe do
  @moduledoc """
  Struct representing a Chef AI recipe -- a curated set of track recommendations
  with deck assignments, cue plans, stem loading instructions, and mixing notes.

  Returned by `SoundForge.DJ.Chef.cook/2` after the LLM parses a natural language
  prompt and the track library is queried for compatible results.
  """

  @type track_recommendation :: %{
          track_id: binary(),
          title: String.t(),
          artist: String.t(),
          tempo: float() | nil,
          key: String.t() | nil,
          energy: float() | nil,
          compatibility_score: float()
        }

  @type deck_assignment :: %{
          deck: 1 | 2,
          track_id: binary(),
          order: non_neg_integer()
        }

  @type cue_plan_entry :: %{
          track_id: binary(),
          cue_type: :hot | :loop_in | :loop_out | :memory,
          position_ms: non_neg_integer(),
          label: String.t()
        }

  @type stem_instruction :: %{
          track_id: binary(),
          stem_type: atom(),
          action: :load | :mute | :solo
        }

  @type t :: %__MODULE__{
          prompt: String.t(),
          parsed_intent: map(),
          tracks: [track_recommendation()],
          deck_assignments: [deck_assignment()],
          cue_plan: [cue_plan_entry()],
          stems_to_load: [stem_instruction()],
          mixing_notes: String.t(),
          generated_at: DateTime.t()
        }

  @enforce_keys [
    :prompt,
    :parsed_intent,
    :tracks,
    :deck_assignments,
    :mixing_notes,
    :generated_at
  ]
  defstruct [
    :prompt,
    :parsed_intent,
    :tracks,
    :deck_assignments,
    :cue_plan,
    :stems_to_load,
    :mixing_notes,
    :generated_at
  ]
end
