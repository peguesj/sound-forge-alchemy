defmodule SoundForge.Music.AnalysisJob do
  @moduledoc """
  Schema for tracking audio analysis jobs via librosa.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_values [:queued, :downloading, :processing, :completed, :failed]

  schema "analysis_jobs" do
    field :status, Ecto.Enum, values: @status_values, default: :queued
    field :progress, :integer, default: 0
    field :results, :map
    field :error, :string

    belongs_to :track, SoundForge.Music.Track
    has_one :analysis_result, SoundForge.Music.AnalysisResult

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(analysis_job, attrs) do
    analysis_job
    |> cast(attrs, [:track_id, :status, :progress, :results, :error])
    |> validate_required([:track_id])
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:track_id)
  end
end
