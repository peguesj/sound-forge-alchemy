defmodule SoundForge.Music.MidiResult do
  @moduledoc """
  Schema for audio-to-MIDI conversion results.
  Stores detected MIDI note data (onset, offset, pitch, velocity) for a track.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "midi_results" do
    field :notes, {:array, :map}

    belongs_to :track, SoundForge.Music.Track

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(midi_result, attrs) do
    midi_result
    |> cast(attrs, [:track_id, :notes])
    |> validate_required([:track_id, :notes])
    |> foreign_key_constraint(:track_id)
  end
end
