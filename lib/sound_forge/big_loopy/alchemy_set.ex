defmodule SoundForge.BigLoopy.AlchemySet do
  @moduledoc """
  Ecto schema for an AlchemySet — the unified data model for BigLoopy.

  An AlchemySet represents a collection of loops or performance pads assembled
  from source tracks via the alchemy pipeline (RecipeParser → OmegaChop → LoopExtractor).

  Types:
    - :loop_set     — A batch of extracted loop segments from one or more tracks
    - :performance_set — A mapped performance layout (pads with loops assigned)
    - :chef_set     — An AI Chef-generated cue/loop collection
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :integer

  @valid_types ~w(loop_set performance_set chef_set)
  @valid_statuses ~w(pending processing complete error)
  @valid_formats ~w(wav mp3 flac)

  schema "alchemy_sets" do
    field :name, :string
    field :type, :string, default: "loop_set"
    field :source_track_ids, {:array, :string}, default: []
    field :recipe, :map, default: %{}
    field :output_format, :string, default: "wav"
    field :status, :string, default: "pending"
    field :zip_path, :string
    field :performance_set, :map, default: %{}

    belongs_to :user, SoundForge.Accounts.User, foreign_key: :user_id, type: :integer

    timestamps()
  end

  @doc "Changeset for creating a new AlchemySet."
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(alchemy_set, attrs) do
    alchemy_set
    |> cast(attrs, [:name, :type, :source_track_ids, :recipe, :output_format, :status, :zip_path, :performance_set, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:output_format, @valid_formats)
  end
end
