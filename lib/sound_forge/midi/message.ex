defmodule SoundForge.MIDI.Message do
  @moduledoc """
  Struct representing a parsed MIDI message.

  ## Fields

    - `type` - atom identifying the message kind (e.g. `:note_on`, `:note_off`,
      `:cc`, `:program_change`, `:sysex`, `:clock`, `:start`, `:stop`, `:continue`)
    - `channel` - 0-based MIDI channel (0..15), `nil` for system messages
    - `data` - map of type-specific fields
    - `timestamp` - monotonic timestamp in microseconds
  """

  @type t :: %__MODULE__{
          type: atom(),
          channel: non_neg_integer() | nil,
          data: map(),
          timestamp: integer()
        }

  @enforce_keys [:type]
  defstruct [:type, :channel, data: %{}, timestamp: 0]
end
