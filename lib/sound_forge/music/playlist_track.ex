defmodule SoundForge.Music.PlaylistTrack do
  @moduledoc """
  Schema for the join table between playlists and tracks, with position ordering.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          position: integer() | nil,
          playlist_id: binary() | nil,
          track_id: binary() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "playlist_tracks" do
    field :position, :integer

    belongs_to :playlist, SoundForge.Music.Playlist
    belongs_to :track, SoundForge.Music.Track

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(playlist_track, attrs) do
    playlist_track
    |> cast(attrs, [:playlist_id, :track_id, :position])
    |> validate_required([:playlist_id, :track_id])
    |> unique_constraint([:playlist_id, :track_id])
    |> foreign_key_constraint(:playlist_id)
    |> foreign_key_constraint(:track_id)
  end
end
