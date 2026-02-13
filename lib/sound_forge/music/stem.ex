defmodule SoundForge.Music.Stem do
  @moduledoc """
  Schema for individual audio stems produced by Demucs separation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @stem_type_values [:vocals, :drums, :bass, :other, :guitar, :piano]

  schema "stems" do
    field :stem_type, Ecto.Enum, values: @stem_type_values
    field :file_path, :string
    field :file_size, :integer

    belongs_to :processing_job, SoundForge.Music.ProcessingJob
    belongs_to :track, SoundForge.Music.Track

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(stem, attrs) do
    stem
    |> cast(attrs, [:processing_job_id, :track_id, :stem_type, :file_path, :file_size])
    |> validate_required([:processing_job_id, :track_id, :stem_type])
    |> validate_inclusion(:stem_type, @stem_type_values)
    |> foreign_key_constraint(:processing_job_id)
    |> foreign_key_constraint(:track_id)
  end
end
