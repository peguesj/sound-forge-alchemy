defmodule SoundForge.Music.ProcessingJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_values [:queued, :downloading, :processing, :completed, :failed]

  schema "processing_jobs" do
    field :model, :string, default: "htdemucs"
    field :status, Ecto.Enum, values: @status_values, default: :queued
    field :progress, :integer, default: 0
    field :output_path, :string
    field :options, :map
    field :error, :string

    belongs_to :track, SoundForge.Music.Track
    has_many :stems, SoundForge.Music.Stem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(processing_job, attrs) do
    processing_job
    |> cast(attrs, [:track_id, :model, :status, :progress, :output_path, :options, :error])
    |> validate_required([:track_id])
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:track_id)
  end
end
