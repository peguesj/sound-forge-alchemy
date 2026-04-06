defmodule SoundForge.DJ.CueSequence do
  @moduledoc """
  Schema for a step-sequenced chain of hot cues.

  Each sequence contains up to 16 steps, where each step can fire a specific
  cue point (by UUID) or be a rest (empty string). The beat clock drives
  step advancement, allowing cue points to be triggered in rhythm.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          name: String.t() | nil,
          step_count: integer(),
          step_cues: [String.t()],
          track_id: binary(),
          user_id: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cue_sequences" do
    field :name, :string
    field :step_count, :integer, default: 16
    field :step_cues, {:array, :string}, default: []

    belongs_to :track, SoundForge.Music.Track
    belongs_to :user, SoundForge.Accounts.User, type: :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(cue_sequence, attrs) do
    cue_sequence
    |> cast(attrs, [:name, :step_count, :step_cues, :track_id, :user_id])
    |> validate_required([:track_id, :user_id])
    |> validate_number(:step_count,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 64
    )
    |> validate_length(:name, max: 100)
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:user_id)
  end
end
