defmodule SoundForge.ControlSurface.OscAdapter do
  @moduledoc """
  ControlSurface adapter for OSC (Open Sound Control) devices.

  Wraps `SoundForge.OSC.Server` to provide a unified control surface interface.
  Primarily used for TouchOSC and other network-based controllers.

  ## Device IDs

  OSC device IDs are formatted as `"osc:{host}:{port}"`, e.g.,
  `"osc:192.168.1.100:9000"` for a TouchOSC client at that address.

  ## Control IDs

  Control IDs are OSC address patterns:

    - `"/stem/1/volume"` - Stem 1 volume fader
    - `"/pad/0"` - Pad 0 trigger
    - `"/transport/play"` - Play button
  """

  @behaviour SoundForge.ControlSurface.Behaviour

  alias SoundForge.OSC.Server
  require Logger

  @impl true
  def init(opts) do
    # OSC.Server is already started by application supervisor
    # This adapter is stateless and delegates to existing OSC infrastructure
    Logger.info("ControlSurface.OscAdapter initialized")
    {:ok, %{opts: opts}}
  end

  @impl true
  def handle_event(event, state) do
    # OSC events are already handled by OSC.Server and broadcast via PubSub
    # to "osc:messages" topic. The Bridge.MidiOsc module translates them.
    Logger.debug("OscAdapter received event: #{inspect(event)}")
    {:ok, state}
  end

  @impl true
  def list_devices do
    # OSC is network-based — devices are not enumerated like USB MIDI.
    # Return the local server as a "listening device."
    port =
      try do
        Server.get_port()
      rescue
        _ -> 8000
      end

    [
      %{
        id: "osc:0.0.0.0:#{port}",
        name: "OSC Server (UDP #{port})",
        type: :osc,
        direction: :input,
        status: :listening
      }
    ]
  end

  @impl true
  def register_mapping(control_id, action, params) do
    case validate_osc_address(control_id) do
      :ok ->
        Logger.info(
          "OscAdapter: registered mapping #{control_id} -> #{action} (#{inspect(params)})"
        )

        # Mapping is stored in DeviceProfile. This callback is a validation hook.
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Private Helpers --

  @doc false
  @spec validate_osc_address(String.t()) :: :ok | {:error, term()}
  def validate_osc_address(address) do
    cond do
      not String.starts_with?(address, "/") ->
        {:error, :invalid_osc_address}

      String.length(address) > 255 ->
        {:error, :address_too_long}

      true ->
        :ok
    end
  end

  @doc """
  Parse an OSC device ID into host and port components.

  ## Examples

      iex> parse_device_id("osc:192.168.1.100:9000")
      {:ok, "192.168.1.100", 9000}

      iex> parse_device_id("osc:localhost:8000")
      {:ok, "localhost", 8000}
  """
  @spec parse_device_id(String.t()) :: {:ok, String.t(), integer()} | {:error, term()}
  def parse_device_id(device_id) do
    case String.split(device_id, ":", parts: 3) do
      ["osc", host, port_str] ->
        case Integer.parse(port_str) do
          {port, ""} -> {:ok, host, port}
          _ -> {:error, :invalid_port}
        end

      _ ->
        {:error, :invalid_device_id}
    end
  end
end
