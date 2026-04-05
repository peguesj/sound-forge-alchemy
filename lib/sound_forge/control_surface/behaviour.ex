defmodule SoundForge.ControlSurface.Behaviour do
  @moduledoc """
  Behaviour for pluggable control surface adapters.

  This abstraction allows MIDI, OSC, and future control protocols (TouchOSC,
  TSI, Rekordbox) to be handled uniformly. Each adapter implements device
  discovery, event handling, and mapping registration.

  ## Example Implementations

    - `SoundForge.ControlSurface.MidiAdapter` - wraps `MIDI.DeviceManager`
    - `SoundForge.ControlSurface.OscAdapter` - wraps `OSC.Server`

  ## Usage

      # Start the adapter
      {:ok, state} = MyAdapter.init(port: 8000)

      # Register a mapping
      :ok = MyAdapter.register_mapping("CC1", :stem_volume, %{target: "master"})

      # Handle incoming event
      {:ok, new_state} = MyAdapter.handle_event(event, state)
  """

  @type device :: %{
          id: String.t(),
          name: String.t(),
          type: atom(),
          direction: atom() | nil,
          status: atom() | nil
        }

  @type event :: term()
  @type state :: term()
  @type control_id :: String.t()
  @type action :: atom()
  @type params :: map()

  @doc """
  Initialize the adapter with the given options.

  Returns `{:ok, state}` on success or `{:error, reason}` on failure.
  """
  @callback init(opts :: keyword()) :: {:ok, state()} | {:error, term()}

  @doc """
  Handle an incoming control event (MIDI message, OSC message, etc.).

  The adapter should parse the event and broadcast it via PubSub for
  the ActionExecutor to consume.

  Returns `{:ok, new_state}` or `{:error, reason}`.
  """
  @callback handle_event(event(), state()) :: {:ok, state()} | {:error, term()}

  @doc """
  List all available devices for this control surface type.

  Returns a list of device maps with `:id`, `:name`, and `:type` keys.
  """
  @callback list_devices() :: [device()]

  @doc """
  Register a mapping between a control ID (e.g., "CC1", "note_48") and
  an application action.

  The `control_id` format is adapter-specific but should uniquely identify
  the control within the device.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @callback register_mapping(control_id(), action(), params()) :: :ok | {:error, term()}
end
