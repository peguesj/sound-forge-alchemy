defmodule SoundForge.DAW.EditOperation do
  @moduledoc """
  Schema for non-destructive DAW edit operations applied to stems.

  Each operation records a transform (crop, trim, fade, split, gain) with
  its parameters and an integer position for deterministic ordering.
  Operations are replayed in position order to produce the final audio.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @operation_types [:crop, :trim, :fade_in, :fade_out, :split, :gain]

  @type t :: %__MODULE__{
          id: binary(),
          stem_id: binary(),
          user_id: integer(),
          operation_type: atom(),
          params: map(),
          position: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "edit_operations" do
    field :operation_type, Ecto.Enum, values: @operation_types
    field :params, :map, default: %{}
    field :position, :integer

    belongs_to :stem, SoundForge.Music.Stem
    belongs_to :user, SoundForge.Accounts.User, type: :id

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(stem_id user_id operation_type params position)a

  @doc false
  def changeset(edit_operation, attrs) do
    edit_operation
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:operation_type, @operation_types)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:stem_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Returns the list of valid operation type atoms.
  """
  @spec operation_types() :: [atom()]
  def operation_types, do: @operation_types
end
