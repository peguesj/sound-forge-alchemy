defmodule SoundForge.MIDI.Mapping do
  @moduledoc """
  Schema for persisting user MIDI controller mappings.

  Maps a specific MIDI message (type + channel + number) on a named device
  to an application action (play, stop, stem_solo, etc.).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          user_id: binary(),
          device_name: String.t(),
          midi_type: atom(),
          channel: integer(),
          number: integer(),
          action: atom(),
          params: map(),
          source: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @midi_types [:cc, :note_on, :note_off]
  @actions [
    :play,
    :stop,
    :next_track,
    :prev_track,
    :stem_solo,
    :stem_mute,
    :stem_volume,
    :seek,
    :bpm_tap,
    :dj_play,
    :dj_cue,
    :dj_crossfader,
    :dj_loop_toggle,
    :dj_loop_size,
    :dj_pitch
  ]

  schema "midi_mappings" do
    field :user_id, :binary_id
    field :device_name, :string
    field :midi_type, Ecto.Enum, values: @midi_types
    field :channel, :integer
    field :number, :integer
    field :action, Ecto.Enum, values: @actions
    field :params, :map, default: %{}
    field :source, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(user_id device_name midi_type channel number action)a
  @optional_fields ~w(params source)a

  @doc false
  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:channel, greater_than_or_equal_to: 0, less_than_or_equal_to: 15)
    |> validate_number(:number, greater_than_or_equal_to: 0, less_than_or_equal_to: 127)
    |> validate_length(:device_name, min: 1, max: 255)
    |> unique_constraint([:user_id, :device_name, :midi_type, :channel, :number])
  end

  @doc """
  Returns the list of valid action atoms.
  """
  @spec actions() :: [atom()]
  def actions, do: @actions

  @doc """
  Returns the list of valid MIDI type atoms.
  """
  @spec midi_types() :: [atom()]
  def midi_types, do: @midi_types
end
