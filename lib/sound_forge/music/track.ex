defmodule SoundForge.Music.Track do
  @moduledoc """
  Schema for audio tracks with Spotify metadata and associated jobs/stems.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @valid_sources ~w(spotify splice manual import)
  @valid_sample_types ~w(full loop one_shot)

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
          source: String.t(),
          sample_type: String.t(),
          drum_categories: [String.t()],
          bpm: float() | nil,
          duration_ms: integer() | nil,
          download_status: String.t() | nil,
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

    # Sample library classification
    field :source, :string, default: "manual"
    field :sample_type, :string, default: "full"
    field :drum_categories, {:array, :string}, default: []
    field :bpm, :float
    field :duration_ms, :integer

    # Stem arrangement grid (Story 3.2) — keyed by stem_type → [{start_sec, end_sec, muted}]
    field :stem_arrangement, :map

    # Virtual field populated by list_tracks query with latest download job status
    field :download_status, :string, virtual: true

    has_many :download_jobs, SoundForge.Music.DownloadJob
    has_many :processing_jobs, SoundForge.Music.ProcessingJob
    has_many :analysis_jobs, SoundForge.Music.AnalysisJob
    has_many :stems, SoundForge.Music.Stem
    has_many :analysis_results, SoundForge.Music.AnalysisResult
    has_many :playlist_tracks, SoundForge.Music.PlaylistTrack
    has_many :playlists, through: [:playlist_tracks, :playlist]

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
      :user_id,
      :source,
      :sample_type,
      :drum_categories,
      :bpm,
      :duration_ms,
      :stem_arrangement
    ])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 500)
    |> validate_number(:duration, greater_than: 0)
    |> validate_inclusion(:source, @valid_sources)
    |> validate_inclusion(:sample_type, @valid_sample_types)
    |> unique_constraint(:spotify_id)
  end
end
