defmodule SoundForge.Music.Track do
  @moduledoc """
  Schema for audio tracks with Spotify metadata and associated jobs/stems.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          spotify_id: String.t() | nil,
          spotify_url: String.t() | nil,
          title: String.t() | nil,
          artist: String.t() | nil,
          album: String.t() | nil,
          album_art_url: String.t() | nil,
          duration: integer() | nil,
          user_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tracks" do
    field :spotify_id, :string
    field :spotify_url, :string
    field :title, :string
    field :artist, :string
    field :album, :string
    field :album_art_url, :string
    field :duration, :integer
    field :user_id, :integer

    has_many :download_jobs, SoundForge.Music.DownloadJob
    has_many :processing_jobs, SoundForge.Music.ProcessingJob
    has_many :analysis_jobs, SoundForge.Music.AnalysisJob
    has_many :stems, SoundForge.Music.Stem
    has_many :analysis_results, SoundForge.Music.AnalysisResult

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(track, attrs) do
    track
    |> cast(attrs, [
      :spotify_id,
      :spotify_url,
      :title,
      :artist,
      :album,
      :album_art_url,
      :duration,
      :user_id
    ])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 500)
    |> validate_number(:duration, greater_than: 0)
    |> unique_constraint(:spotify_id)
  end
end
