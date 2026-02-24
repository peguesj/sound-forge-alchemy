defmodule SoundForge.DJ.DeckSession do
  @moduledoc """
  Schema for an active DJ deck session.

  Tracks the state of each virtual deck (1 or 2) including the loaded track,
  tempo, pitch adjustment, and any active loop region.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          deck_number: integer(),
          track_id: binary() | nil,
          user_id: integer(),
          tempo_bpm: float() | nil,
          pitch_adjust: float(),
          loop_start_ms: integer() | nil,
          loop_end_ms: integer() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "deck_sessions" do
    field :deck_number, :integer
    field :tempo_bpm, :float
    field :pitch_adjust, :float, default: 0.0
    field :loop_start_ms, :integer
    field :loop_end_ms, :integer

    belongs_to :track, SoundForge.Music.Track
    belongs_to :user, SoundForge.Accounts.User, type: :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck_session, attrs) do
    deck_session
    |> cast(attrs, [
      :deck_number,
      :track_id,
      :user_id,
      :tempo_bpm,
      :pitch_adjust,
      :loop_start_ms,
      :loop_end_ms
    ])
    |> validate_required([:deck_number, :user_id])
    |> validate_inclusion(:deck_number, 1..2)
    |> validate_number(:pitch_adjust,
      greater_than_or_equal_to: -8.0,
      less_than_or_equal_to: 8.0
    )
    |> validate_number(:tempo_bpm, greater_than: 0)
    |> validate_number(:loop_start_ms, greater_than_or_equal_to: 0)
    |> validate_number(:loop_end_ms, greater_than_or_equal_to: 0)
    |> validate_loop_range()
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :deck_number])
  end

  defp validate_loop_range(changeset) do
    loop_start = get_field(changeset, :loop_start_ms)
    loop_end = get_field(changeset, :loop_end_ms)

    cond do
      is_nil(loop_start) or is_nil(loop_end) ->
        changeset

      loop_end <= loop_start ->
        add_error(changeset, :loop_end_ms, "must be greater than loop_start_ms")

      true ->
        changeset
    end
  end
end
