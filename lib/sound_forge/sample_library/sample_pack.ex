defmodule SoundForge.SampleLibrary.SamplePack do
  @moduledoc """
  Ecto schema for a SamplePack — a collection of sample files from a common source.

  A SamplePack groups related audio samples (e.g., a Splice sample pack,
  a local folder of drums, or a freesound collection) under a single entity
  with shared metadata like category, BPM range, and musical key.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :integer

  @valid_sources ~w(splice freesound local upload)
  @valid_statuses ~w(pending importing ready error)
  @valid_categories ~w(drums bass synths vocals loops sfx mixed)

  schema "sample_packs" do
    field :name, :string
    field :source, :string, default: "local"
    field :category, :string
    field :bpm_range_min, :float
    field :bpm_range_max, :float
    field :key, :string
    field :total_files, :integer, default: 0
    field :manifest_path, :string
    field :status, :string, default: "pending"

    belongs_to :user, SoundForge.Accounts.User, foreign_key: :user_id, type: :integer
    has_many :sample_files, SoundForge.SampleLibrary.SampleFile, foreign_key: :pack_id

    timestamps()
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(pack, attrs) do
    pack
    |> cast(attrs, [:name, :source, :category, :bpm_range_min, :bpm_range_max, :key,
                    :total_files, :manifest_path, :status, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_inclusion(:source, @valid_sources)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:category, @valid_categories ++ [nil])
  end
end
