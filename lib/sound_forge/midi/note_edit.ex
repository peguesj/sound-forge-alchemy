defmodule SoundForge.MIDI.NoteEdit do
  @moduledoc """
  Schema for user-created MIDI note edits on a track's piano roll.

  Stores notes drawn by the user in the piano roll view, overlaid on top
  of auto-detected MIDI notes from the analysis pipeline.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          note: integer(),
          onset_sec: float(),
          duration_sec: float(),
          velocity: float(),
          track_id: binary(),
          user_id: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "midi_note_edits" do
    field :note, :integer
    field :onset_sec, :float
    field :duration_sec, :float, default: 0.25
    field :velocity, :float, default: 0.8

    belongs_to :track, SoundForge.Music.Track
    belongs_to :user, SoundForge.Accounts.User, type: :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(note_edit, attrs) do
    note_edit
    |> cast(attrs, [:note, :onset_sec, :duration_sec, :velocity, :track_id, :user_id])
    |> validate_required([:note, :onset_sec, :track_id, :user_id])
    |> validate_number(:note, greater_than_or_equal_to: 0, less_than_or_equal_to: 127)
    |> validate_number(:onset_sec, greater_than_or_equal_to: 0.0)
    |> validate_number(:duration_sec, greater_than_or_equal_to: 0.01)
    |> validate_number(:velocity, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:user_id)
  end
end
