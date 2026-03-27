defmodule SoundForge.Daw.DawProject do
  @moduledoc """
  Schema for a DAW project, representing a user's multi-track arrangement session.

  Each project has top-level metadata (BPM, key, time signature) and a collection
  of `DawProjectTrack` entries that reference source audio files and hold positional
  and type information.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "daw_projects" do
    field :title, :string, default: "Untitled Project"
    field :bpm, :integer, default: 120
    field :key, :string
    field :time_sig, :string, default: "4/4"
    field :settings, :map, default: %{}

    # user_id is an integer FK — users table has a serial (integer) PK
    belongs_to :user, SoundForge.Accounts.User, type: :integer

    has_many :project_tracks, SoundForge.Daw.DawProjectTrack

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(daw_project, attrs) do
    daw_project
    |> cast(attrs, [:title, :bpm, :key, :time_sig, :settings, :user_id])
    |> validate_required([:title, :user_id])
  end
end
