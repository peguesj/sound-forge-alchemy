defmodule SoundForge.Music.ChordResult do
  @moduledoc """
  Schema for chord detection results.
  Stores detected chord progressions and detected key for a track.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chord_results" do
    field :chords, {:array, :map}
    field :key, :string

    belongs_to :track, SoundForge.Music.Track

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chord_result, attrs) do
    chord_result
    |> cast(attrs, [:track_id, :chords, :key])
    |> validate_required([:track_id, :chords])
    |> foreign_key_constraint(:track_id)
  end
end
