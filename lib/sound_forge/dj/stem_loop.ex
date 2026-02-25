defmodule SoundForge.DJ.StemLoop do
  @moduledoc """
  Schema for user-created stem loop regions.

  Represents a loop region on a specific stem of a track. Users can create
  custom loops by marking start/end positions on individual stems (vocals,
  drums, bass, etc.) within the DJ tab. These loops can be auditioned
  independently and set as the active deck loop.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          stem_id: binary(),
          track_id: binary(),
          user_id: integer(),
          label: String.t() | nil,
          start_ms: integer(),
          end_ms: integer(),
          color: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stem_loops" do
    field :label, :string
    field :start_ms, :integer
    field :end_ms, :integer
    field :color, :string

    belongs_to :stem, SoundForge.Music.Stem
    belongs_to :track, SoundForge.Music.Track
    belongs_to :user, SoundForge.Accounts.User, type: :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(stem_loop, attrs) do
    stem_loop
    |> cast(attrs, [:stem_id, :track_id, :user_id, :label, :start_ms, :end_ms, :color])
    |> validate_required([:stem_id, :track_id, :user_id, :start_ms, :end_ms])
    |> validate_number(:start_ms, greater_than_or_equal_to: 0)
    |> validate_number(:end_ms, greater_than_or_equal_to: 0)
    |> validate_loop_range()
    |> validate_length(:label, max: 100)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/,
      message: "must be a hex color (e.g. #FF0000)"
    )
    |> foreign_key_constraint(:stem_id)
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_loop_range(changeset) do
    start_ms = get_field(changeset, :start_ms)
    end_ms = get_field(changeset, :end_ms)

    cond do
      is_nil(start_ms) or is_nil(end_ms) ->
        changeset

      end_ms <= start_ms ->
        add_error(changeset, :end_ms, "must be greater than start_ms")

      true ->
        changeset
    end
  end
end
