defmodule SoundForge.DJ.ChefSetItem do
  @moduledoc """
  A single cue point, loop marker, or beat annotation within a ChefSet.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @item_types ~w(hot_cue memory_cue loop beat_marker)

  schema "chef_set_items" do
    field :position_ms, :integer
    field :end_ms, :integer
    field :label, :string
    field :confidence, :float
    field :item_type, :string, default: "hot_cue"
    field :color, :string
    field :sort_order, :integer

    belongs_to :chef_set, SoundForge.DJ.ChefSet

    timestamps()
  end

  @type t :: %__MODULE__{}

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = item, attrs) do
    item
    |> cast(attrs, [:position_ms, :end_ms, :label, :confidence, :item_type, :color, :sort_order, :chef_set_id])
    |> validate_required([:position_ms, :item_type, :chef_set_id])
    |> validate_inclusion(:item_type, @item_types)
    |> validate_number(:position_ms, greater_than_or_equal_to: 0)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end
