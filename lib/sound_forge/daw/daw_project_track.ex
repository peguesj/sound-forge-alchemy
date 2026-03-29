defmodule SoundForge.Daw.DawProjectTrack do
  @moduledoc """
  Schema for an individual track lane within a DAW project.

  Each record represents one track in the arrangement:
  - `daw_project_id` — the parent project (required)
  - `audio_file_id`  — optional reference to a source audio file in the `tracks` table
  - `position`       — zero-based ordering of the track within the project
  - `track_type`     — semantic type (e.g. "audio", "stem", "midi", "unknown")
  - `metadata`       — arbitrary extra data (e.g. colour, solo/mute state, clip regions)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "daw_project_tracks" do
    field :title, :string
    field :position, :integer, default: 0
    field :track_type, :string, default: "unknown"
    field :metadata, :map, default: %{}

    belongs_to :daw_project, SoundForge.Daw.DawProject

    # audio_file_id references the tracks table (nullable)
    belongs_to :audio_file, SoundForge.Music.Track,
      foreign_key: :audio_file_id,
      references: :id,
      type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(daw_project_track, attrs) do
    daw_project_track
    |> cast(attrs, [:title, :position, :track_type, :metadata, :daw_project_id, :audio_file_id])
    |> validate_required([:daw_project_id, :position, :track_type])
  end
end
