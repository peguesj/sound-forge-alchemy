defmodule SoundForge.Bridge.MidiOsc do
  @moduledoc """
  Bidirectional bridge between MIDI and OSC protocols.

  Translates OSC messages from TouchOSC into MIDI messages and vice versa,
  enabling hardware MIDI controllers and TouchOSC to control the same actions.
  """
  use GenServer
  require Logger

  @default_touchosc_host "192.168.1.255"
  @default_touchosc_port 9000

  defstruct [
    :touchosc_host,
    :touchosc_port,
    enabled: true,
    mappings: %{},
    midi_subscriptions: []
  ]

  # -- Public API --

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Update the mapping table."
  def set_mapping(mapping, server \\ __MODULE__) do
    GenServer.call(server, {:set_mapping, mapping})
  end

  @doc "Set the TouchOSC target address."
  def set_touchosc_target(host, port, server \\ __MODULE__) do
    GenServer.call(server, {:set_target, host, port})
  end

  @doc "Enable or disable the bridge."
  def set_enabled(enabled, server \\ __MODULE__) do
    GenServer.call(server, {:set_enabled, enabled})
  end

  @doc "Get current bridge state."
  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end

  # -- GenServer Callbacks --

  @impl true
  def init(opts) do
    host = Keyword.get(opts, :touchosc_host, @default_touchosc_host)
    port = Keyword.get(opts, :touchosc_port, @default_touchosc_port)

    # Subscribe to OSC messages
    Phoenix.PubSub.subscribe(SoundForge.PubSub, "osc:messages")

    state = %__MODULE__{
      touchosc_host: host,
      touchosc_port: port,
      mappings: default_mappings()
    }

    Logger.info("MIDI-OSC Bridge started (target: #{host}:#{port})")
    {:ok, state}
  end

  @impl true
  def handle_call({:set_mapping, mapping}, _from, state) do
    {:reply, :ok, %{state | mappings: mapping}}
  end

  def handle_call({:set_target, host, port}, _from, state) do
    {:reply, :ok, %{state | touchosc_host: host, touchosc_port: port}}
  end

  def handle_call({:set_enabled, enabled}, _from, state) do
    {:reply, :ok, %{state | enabled: enabled}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, Map.from_struct(state), state}
  end

  # OSC -> MIDI translation
  @impl true
  def handle_info({:osc_message, _msg, _sender}, %{enabled: false} = state) do
    {:noreply, state}
  end

  def handle_info({:osc_message, %{address: address, args: args}, _sender}, state) do
    case translate_osc_to_midi(address, args, state.mappings) do
      {:ok, midi_msg} ->
        # Broadcast as MIDI message for other consumers
        Phoenix.PubSub.broadcast(SoundForge.PubSub, "midi:bridge", {:midi_from_osc, midi_msg})

      :ignored ->
        Logger.debug("OSC bridge: no mapping for #{address}")
    end

    {:noreply, state}
  end

  # MIDI -> OSC translation (subscribed by action_executor or other consumers)
  def handle_info({:midi_state_change, %{type: :cc, channel: ch, number: cc, value: val}}, state) do
    if state.enabled do
      case translate_midi_to_osc(ch, cc, val, state.mappings) do
        {:ok, address, osc_args} ->
          SoundForge.OSC.Client.send(state.touchosc_host, state.touchosc_port, address, osc_args)

        :ignored ->
          :ok
      end
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- Translation Logic --

  defp translate_osc_to_midi(address, args, mappings) do
    case parse_osc_address(address) do
      {:stem, n, :volume} ->
        value = osc_float_to_midi(List.first(args) || 0.0)
        {:ok, %{type: :cc, channel: 1, number: 6 + n, value: value}}

      {:stem, n, :mute} ->
        on = if List.first(args) == 1.0, do: 127, else: 0
        {:ok, %{type: :cc, channel: 1, number: 16 + n, value: on}}

      {:stem, n, :solo} ->
        on = if List.first(args) == 1.0, do: 127, else: 0
        {:ok, %{type: :cc, channel: 1, number: 32 + n, value: on}}

      {:pad, n} ->
        velocity = round((List.first(args) || 1.0) * 127)
        type = if velocity > 0, do: :note_on, else: :note_off
        {:ok, %{type: type, channel: 10, note: 35 + n, velocity: velocity}}

      {:transport, action} ->
        {:ok, %{type: :transport, action: action}}

      :unknown ->
        # Check custom mappings
        case Map.get(mappings, address) do
          nil -> :ignored
          mapping -> {:ok, mapping}
        end
    end
  end

  defp translate_midi_to_osc(channel, cc, value, _mappings) do
    cond do
      channel == 1 and cc in 7..14 ->
        stem = cc - 6
        {:ok, "/stem/#{stem}/volume", [midi_to_osc_float(value)]}

      channel == 1 and cc in 17..24 ->
        stem = cc - 16
        {:ok, "/stem/#{stem}/mute", [if(value > 63, do: 1.0, else: 0.0)]}

      channel == 1 and cc in 33..40 ->
        stem = cc - 32
        {:ok, "/stem/#{stem}/solo", [if(value > 63, do: 1.0, else: 0.0)]}

      true ->
        :ignored
    end
  end

  defp parse_osc_address("/stem/" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [n_str, "volume"] -> {:stem, parse_int(n_str), :volume}
      [n_str, "mute"] -> {:stem, parse_int(n_str), :mute}
      [n_str, "solo"] -> {:stem, parse_int(n_str), :solo}
      _ -> :unknown
    end
  end

  defp parse_osc_address("/pad/" <> n_str), do: {:pad, parse_int(n_str)}
  defp parse_osc_address("/transport/play"), do: {:transport, :play}
  defp parse_osc_address("/transport/stop"), do: {:transport, :stop}
  defp parse_osc_address("/transport/next"), do: {:transport, :next_track}
  defp parse_osc_address("/transport/prev"), do: {:transport, :prev_track}
  defp parse_osc_address(_), do: :unknown

  defp osc_float_to_midi(f) when is_float(f), do: round(f * 127) |> max(0) |> min(127)
  defp osc_float_to_midi(_), do: 0

  defp midi_to_osc_float(v) when is_integer(v), do: v / 127.0
  defp midi_to_osc_float(_), do: 0.0

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp default_mappings do
    %{
      # Custom OSC paths can be added here
    }
  end
end
