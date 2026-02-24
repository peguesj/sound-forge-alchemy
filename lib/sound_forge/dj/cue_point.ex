defmodule SoundForge.DJ.CuePoint do
  @moduledoc """
  Schema for DJ cue points on a track.

  Supports hot cues, loop-in/out markers, and memory cues that persist
  per-user per-track for quick navigation during DJ sessions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @cue_types [:hot, :loop_in, :loop_out, :memory]

  @type t :: %__MODULE__{
          id: binary(),
          track_id: binary(),
          user_id: integer(),
          position_ms: integer(),
          label: String.t() | nil,
          color: String.t() | nil,
          cue_type: :hot | :loop_in | :loop_out | :memory,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cue_points" do
    field :position_ms, :integer
    field :label, :string
    field :color, :string
    field :cue_type, Ecto.Enum, values: @cue_types

    belongs_to :track, SoundForge.Music.Track
    belongs_to :user, SoundForge.Accounts.User, type: :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(cue_point, attrs) do
    cue_point
    |> cast(attrs, [:track_id, :user_id, :position_ms, :label, :color, :cue_type])
    |> validate_required([:track_id, :user_id, :position_ms, :cue_type])
    |> validate_number(:position_ms, greater_than_or_equal_to: 0)
    |> validate_inclusion(:cue_type, @cue_types)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a hex color (e.g. #FF0000)")
    |> validate_length(:label, max: 100)
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Returns the list of valid cue type atoms.
  """
  @spec cue_types() :: [atom()]
  def cue_types, do: @cue_types
end
