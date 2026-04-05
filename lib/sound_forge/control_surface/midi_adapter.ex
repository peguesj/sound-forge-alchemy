defmodule SoundForge.ControlSurface.MidiAdapter do
  @moduledoc """
  ControlSurface adapter for MIDI hardware controllers.

  Wraps `SoundForge.MIDI.DeviceManager` and `MIDI.Dispatcher` to provide
  a unified control surface interface. All existing MIDI Learn functionality
  is preserved.

  ## Device IDs

  MIDI device IDs follow the format: `"midi:{direction}:{port_num}"`, e.g.,
  `"midi:input:0"` for the first input port.

  ## Control IDs

  Control IDs are formatted as `"{midi_type}:{channel}:{number}"`:

    - `"cc:0:1"` - Control Change 1 on channel 0
    - `"note_on:0:48"` - Note On C3 (48) on channel 0
    - `"note_off:0:48"` - Note Off C3 (48) on channel 0
  """

  @behaviour SoundForge.ControlSurface.Behaviour

  alias SoundForge.MIDI.DeviceManager
  require Logger

  @impl true
  def init(opts) do
    # MIDI.DeviceManager and Dispatcher are already started by application supervisor
    # This adapter is stateless — it delegates to existing infrastructure
    Logger.info("ControlSurface.MidiAdapter initialized")
    {:ok, %{opts: opts}}
  end

  @impl true
  def handle_event(event, state) do
    # MIDI events are already handled by MIDI.Dispatcher and broadcast via PubSub.
    # This callback is provided for future extensions where the adapter might
    # transform or filter events before broadcasting.
    Logger.debug("MidiAdapter received event: #{inspect(event)}")
    {:ok, state}
  end

  @impl true
  def list_devices do
    DeviceManager.list_devices()
    |> Enum.map(fn device ->
      %{
        id: "midi:#{device.port_id}",
        name: device.name,
        type: :midi,
        direction: device.direction,
        status: device.status
      }
    end)
  end

  @impl true
  def register_mapping(control_id, action, params) do
    case parse_control_id(control_id) do
      {:ok, _midi_type, _channel, _number} ->
        Logger.info(
          "MidiAdapter: registered mapping #{control_id} -> #{action} (#{inspect(params)})"
        )

        # The actual mapping is persisted via MIDI.Mappings context when the user
        # completes MIDI Learn. This callback is a hook for future extensions
        # (e.g., validating the control exists on the device).
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Private Helpers --

  @doc false
  @spec parse_control_id(String.t()) :: {:ok, atom(), integer(), integer()} | {:error, term()}
  def parse_control_id(control_id) do
    case String.split(control_id, ":", parts: 3) do
      [midi_type_str, channel_str, number_str] ->
        with {:ok, midi_type} <- parse_midi_type(midi_type_str),
             {channel, ""} <- Integer.parse(channel_str),
             {number, ""} <- Integer.parse(number_str) do
          {:ok, midi_type, channel, number}
        else
          _ -> {:error, :invalid_control_id}
        end

      _ ->
        {:error, :invalid_control_id}
    end
  end

  defp parse_midi_type("cc"), do: {:ok, :cc}
  defp parse_midi_type("note_on"), do: {:ok, :note_on}
  defp parse_midi_type("note_off"), do: {:ok, :note_off}
  defp parse_midi_type(_), do: {:error, :unknown_midi_type}

  @doc """
  Format a MIDI message as a control ID string.

  ## Examples

      iex> format_control_id(:cc, 0, 1)
      "cc:0:1"

      iex> format_control_id(:note_on, 0, 48)
      "note_on:0:48"
  """
  @spec format_control_id(atom(), integer(), integer()) :: String.t()
  def format_control_id(midi_type, channel, number) do
    "#{midi_type}:#{channel}:#{number}"
  end
end
