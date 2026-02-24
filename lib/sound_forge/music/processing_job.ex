defmodule SoundForge.Music.ProcessingJob do
  @moduledoc """
  Schema for tracking stem separation processing jobs via Demucs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          model: String.t() | nil,
          status: :queued | :downloading | :processing | :completed | :failed,
          progress: integer(),
          output_path: String.t() | nil,
          options: map() | nil,
          error: String.t() | nil,
          track_id: binary() | nil,
          batch_job_id: binary() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

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
    field :engine, :string, default: "demucs"
    field :preview, :boolean, default: false

    belongs_to :track, SoundForge.Music.Track
    belongs_to :batch_job, SoundForge.Music.BatchJob
    has_many :stems, SoundForge.Music.Stem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(processing_job, attrs) do
    processing_job
    |> cast(attrs, [:track_id, :batch_job_id, :model, :status, :progress, :output_path, :options, :error, :engine, :preview])
    |> validate_required([:track_id])
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:track_id)
  end
end
