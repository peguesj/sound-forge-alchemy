defmodule SoundForge.Sampler.Bank do
  @moduledoc """
  Schema for a sampler pad bank.

  Each bank belongs to a user and contains up to 16 pads (4x4 grid).
  Banks can be named, colored, and reordered via the `position` field.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          name: String.t(),
          color: String.t() | nil,
          position: integer(),
          bpm: float() | nil,
          user_id: integer(),
          pads: [SoundForge.Sampler.Pad.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sampler_banks" do
    field :name, :string, default: "Bank A"
    field :color, :string, default: "#8b5cf6"
    field :position, :integer, default: 0
    field :bpm, :float
    field :user_id, :integer

    has_many :pads, SoundForge.Sampler.Pad

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bank, attrs) do
    bank
    |> cast(attrs, [:name, :color, :position, :bpm, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 100)
  end
end
