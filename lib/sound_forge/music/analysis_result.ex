defmodule SoundForge.Music.AnalysisResult do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "analysis_results" do
    field :tempo, :float
    field :key, :string
    field :energy, :float
    field :spectral_centroid, :float
    field :spectral_rolloff, :float
    field :zero_crossing_rate, :float
    field :features, :map

    belongs_to :track, SoundForge.Music.Track
    belongs_to :analysis_job, SoundForge.Music.AnalysisJob

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(analysis_result, attrs) do
    analysis_result
    |> cast(attrs, [
      :track_id,
      :analysis_job_id,
      :tempo,
      :key,
      :energy,
      :spectral_centroid,
      :spectral_rolloff,
      :zero_crossing_rate,
      :features
    ])
    |> validate_required([:track_id, :analysis_job_id])
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:analysis_job_id)
  end
end
