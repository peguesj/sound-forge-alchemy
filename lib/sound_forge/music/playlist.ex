defmodule SoundForge.Music.Playlist do
  @moduledoc """
  Schema for playlists containing tracks with Spotify metadata.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          name: String.t() | nil,
          description: String.t() | nil,
          spotify_id: String.t() | nil,
          spotify_url: String.t() | nil,
          cover_art_url: String.t() | nil,
          user_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "playlists" do
    field :name, :string
    field :description, :string
    field :spotify_id, :string
    field :spotify_url, :string
    field :cover_art_url, :string
    field :source, :string, default: "manual"
    field :user_id, :integer

    has_many :playlist_tracks, SoundForge.Music.PlaylistTrack
    has_many :tracks, through: [:playlist_tracks, :track]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(playlist, attrs) do
    playlist
    |> cast(attrs, [:name, :description, :spotify_id, :spotify_url, :cover_art_url, :source, :user_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 500)
    |> validate_inclusion(:source, ~w(spotify manual import))
    |> unique_constraint([:spotify_id, :user_id])
  end
end
