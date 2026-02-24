defmodule SoundForge.Music.Stem do
  @moduledoc """
  Schema for individual audio stems produced by Demucs separation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          stem_type:
            :vocals
            | :drums
            | :bass
            | :other
            | :guitar
            | :piano
            | :electric_guitar
            | :acoustic_guitar
            | :synth
            | :strings
            | :wind,
          file_path: String.t() | nil,
          file_size: integer() | nil,
          options: map() | nil,
          processing_job_id: binary() | nil,
          track_id: binary() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Includes original Demucs types plus extended lalal.ai types
  @stem_type_values [
    :vocals,
    :drums,
    :bass,
    :other,
    :guitar,
    :piano,
    :electric_guitar,
    :acoustic_guitar,
    :synth,
    :strings,
    :wind
  ]

  schema "stems" do
    field :stem_type, Ecto.Enum, values: @stem_type_values
    field :file_path, :string
    field :file_size, :integer
    field :options, :map, default: %{}
    field :source, :string, default: "local"

    belongs_to :processing_job, SoundForge.Music.ProcessingJob
    belongs_to :track, SoundForge.Music.Track

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(stem, attrs) do
    stem
    |> cast(attrs, [
      :processing_job_id,
      :track_id,
      :stem_type,
      :file_path,
      :file_size,
      :options,
      :source
    ])
    |> validate_required([:processing_job_id, :track_id, :stem_type])
    |> validate_inclusion(:stem_type, @stem_type_values)
    |> foreign_key_constraint(:processing_job_id)
    |> foreign_key_constraint(:track_id)
  end

  @doc """
  Changeset for DAW-exported stems. Does not require `processing_job_id`
  since edited stems are created directly by the user, not by a processing job.
  """
  def export_changeset(stem, attrs) do
    stem
    |> cast(attrs, [:track_id, :stem_type, :file_path, :file_size, :options, :source])
    |> validate_required([:track_id, :stem_type])
    |> validate_inclusion(:stem_type, @stem_type_values)
    |> foreign_key_constraint(:track_id)
  end
end
