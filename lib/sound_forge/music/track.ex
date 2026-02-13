defmodule SoundForge.Music.Track do
  use Ecto.Schema
  import Ecto.Changeset

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
    |> cast(attrs, [:spotify_id, :spotify_url, :title, :artist, :album, :album_art_url, :duration, :user_id])
    |> validate_required([:title])
    |> unique_constraint(:spotify_id)
  end
end
