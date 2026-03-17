defmodule SoundForge.SampleLibrary.SampleFile do
  @moduledoc """
  Ecto schema for a SampleFile — a single audio sample within a SamplePack.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(one_shot loop texture fill)
  @valid_categories ~w(drums bass synths vocals sfx misc)

  schema "sample_files" do
    field :name, :string
    field :file_path, :string
    field :duration_ms, :integer
    field :bpm, :float
    field :key, :string
    field :file_size, :integer
    field :sample_type, :string
    field :category, :string
    field :preview_url, :string
    field :tags, {:array, :string}, default: []

    belongs_to :pack, SoundForge.SampleLibrary.SamplePack, foreign_key: :pack_id

    timestamps()
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(file, attrs) do
    file
    |> cast(attrs, [:name, :file_path, :duration_ms, :bpm, :key, :file_size,
                    :sample_type, :category, :preview_url, :tags, :pack_id])
    |> validate_required([:name, :file_path, :pack_id])
    |> validate_inclusion(:sample_type, @valid_types ++ [nil])
    |> validate_inclusion(:category, @valid_categories ++ [nil])
  end
end
