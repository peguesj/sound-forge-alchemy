defmodule SoundForge.MIDI.MPCController do
  @moduledoc """
  GenServer that bridges MPC pad input to stem playback actions with LED feedback.

  Subscribes to MIDI messages from detected MPC devices via the Dispatcher's
  PubSub topics. On pad note_on, broadcasts `{:stem_trigger, stem_index, velocity}`
  on `"midi:actions"`. On note_off in `:hold` mode, broadcasts
  `{:stem_release, stem_index}`.

  Subscribes to `"midi:stem_states"` for stem state changes and sends LED
  color feedback via `SoundForge.MIDI.Output.send_sysex/2`:
  - green = playing
  - red = muted
  - blue = soloed
  - off = inactive

  ## Configuration

  Pad trigger mode is configurable per-instance:
  - `:hold` — note_off releases the stem
  - `:toggle` — note_on toggles playback, note_off is ignored

  Default pad-to-stem assignment: pads 0-3 map to stem indices 0-3
  (vocals, drums, bass, other).
  """

  use GenServer

  require Logger

  alias SoundForge.MIDI.{DeviceManager, Output, Profiles.MPC}

  @pubsub SoundForge.PubSub
  @actions_topic "midi:actions"
  @stem_states_topic "midi:stem_states"

  @default_pad_stem_map %{
    0 => 0,
    1 => 1,
    2 => 2,
    3 => 3
  }

  @pad_note_offset 36

  @type mode :: :hold | :toggle
  @type stem_state :: :playing | :muted | :soloed | :inactive

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the MPCController GenServer.

  ## Options

    - `:mode` - `:hold` or `:toggle` (default: `:hold`)
    - `:pad_stem_map` - map of pad_index => stem_index (default: pads 0-3 to stems 0-3)
    - `:name` - GenServer name (default: `__MODULE__`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Sets the trigger mode to `:hold` or `:toggle`.
  """
  @spec set_mode(GenServer.server(), mode()) :: :ok
  def set_mode(server \\ __MODULE__, mode) when mode in [:hold, :toggle] do
    GenServer.call(server, {:set_mode, mode})
  end

  @doc """
  Returns the current trigger mode.
  """
  @spec get_mode(GenServer.server()) :: mode()
  def get_mode(server \\ __MODULE__) do
    GenServer.call(server, :get_mode)
  end

  @doc """
  Updates the pad-to-stem assignment map.
  """
  @spec set_pad_stem_map(GenServer.server(), %{non_neg_integer() => non_neg_integer()}) :: :ok
  def set_pad_stem_map(server \\ __MODULE__, pad_stem_map) when is_map(pad_stem_map) do
    GenServer.call(server, {:set_pad_stem_map, pad_stem_map})
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    mode = Keyword.get(opts, :mode, :hold)
    pad_stem_map = Keyword.get(opts, :pad_stem_map, @default_pad_stem_map)

    # Subscribe to stem state changes for LED feedback
    Phoenix.PubSub.subscribe(@pubsub, @stem_states_topic)

    # Subscribe to device connect/disconnect for dynamic MPC detection
    Phoenix.PubSub.subscribe(@pubsub, "midi:devices")

    # Find already-connected MPC devices and subscribe to their messages
    mpc_devices = discover_mpc_devices()

    for {port_id, _model} <- mpc_devices do
      Phoenix.PubSub.subscribe(@pubsub, "midi:messages:#{port_id}")
    end

    state = %{
      mode: mode,
      pad_stem_map: pad_stem_map,
      mpc_devices: mpc_devices,
      stem_states: %{}
    }

    Logger.info(
      "MPCController started: mode=#{mode}, " <>
        "devices=#{map_size(mpc_devices)}, " <>
        "pad_stem_map=#{inspect(pad_stem_map)}"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:set_mode, mode}, _from, state) do
    Logger.info("MPCController mode changed to #{mode}")
    {:reply, :ok, %{state | mode: mode}}
  end

  def handle_call(:get_mode, _from, state) do
    {:reply, state.mode, state}
  end

  def handle_call({:set_pad_stem_map, pad_stem_map}, _from, state) do
    Logger.info("MPCController pad_stem_map updated: #{inspect(pad_stem_map)}")
    {:reply, :ok, %{state | pad_stem_map: pad_stem_map}}
  end

  @impl true
  def handle_info({:midi_message, port_id, %{type: :note_on, data: data}}, state) do
    case Map.get(state.mpc_devices, port_id) do
      nil ->
        {:noreply, state}

      _model ->
        handle_note_on(data, state)
    end
  end

  def handle_info({:midi_message, port_id, %{type: :note_off, data: data}}, state) do
    case Map.get(state.mpc_devices, port_id) do
      nil ->
        {:noreply, state}

      _model ->
        handle_note_off(data, state)
    end
  end

  def handle_info({:midi_message, _port_id, _message}, state) do
    {:noreply, state}
  end

  # Device hotplug: new MPC connected
  def handle_info({:midi_device_connected, device}, state) do
    case MPC.detect(device.name) do
      {:ok, model} ->
        port_id = device.port_id
        Phoenix.PubSub.subscribe(@pubsub, "midi:messages:#{port_id}")

        Logger.info(
          "MPCController detected new MPC device: #{device.name} (#{model}) on port #{port_id}"
        )

        mpc_devices = Map.put(state.mpc_devices, port_id, model)
        {:noreply, %{state | mpc_devices: mpc_devices}}

      :unknown ->
        {:noreply, state}
    end
  end

  # Device hotplug: MPC disconnected
  def handle_info({:midi_device_disconnected, device}, state) do
    port_id = device.port_id

    if Map.has_key?(state.mpc_devices, port_id) do
      Phoenix.PubSub.unsubscribe(@pubsub, "midi:messages:#{port_id}")
      Logger.info("MPCController lost MPC device on port #{port_id}")
      mpc_devices = Map.delete(state.mpc_devices, port_id)
      {:noreply, %{state | mpc_devices: mpc_devices}}
    else
      {:noreply, state}
    end
  end

  # Stem state change: update LEDs
  def handle_info({:stem_state_changed, stem_index, new_state}, state) do
    stem_states = Map.put(state.stem_states, stem_index, new_state)
    state = %{state | stem_states: stem_states}
    update_led_for_stem(stem_index, new_state, state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private: Pad Input Handling
  # ---------------------------------------------------------------------------

  defp handle_note_on(%{note: note, velocity: velocity}, state) do
    pad_index = note - @pad_note_offset

    case Map.get(state.pad_stem_map, pad_index) do
      nil ->
        {:noreply, state}

      stem_index ->
        Phoenix.PubSub.broadcast(
          @pubsub,
          @actions_topic,
          {:stem_trigger, stem_index, velocity}
        )

        Logger.debug(
          "MPCController pad #{pad_index} -> stem #{stem_index}, velocity=#{velocity}"
        )

        {:noreply, state}
    end
  end

  defp handle_note_on(_data, state), do: {:noreply, state}

  defp handle_note_off(%{note: note}, state) do
    case state.mode do
      :hold ->
        pad_index = note - @pad_note_offset

        case Map.get(state.pad_stem_map, pad_index) do
          nil ->
            {:noreply, state}

          stem_index ->
            Phoenix.PubSub.broadcast(
              @pubsub,
              @actions_topic,
              {:stem_release, stem_index}
            )

            Logger.debug("MPCController pad #{pad_index} released -> stem #{stem_index}")
            {:noreply, state}
        end

      :toggle ->
        {:noreply, state}
    end
  end

  defp handle_note_off(_data, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private: LED Feedback
  # ---------------------------------------------------------------------------

  @spec state_to_color(stem_state()) :: MPC.color()
  defp state_to_color(:playing), do: :green
  defp state_to_color(:muted), do: :red
  defp state_to_color(:soloed), do: :blue
  defp state_to_color(:inactive), do: :off

  defp update_led_for_stem(stem_index, stem_state, state) do
    color = state_to_color(stem_state)

    # Find pad indices mapped to this stem
    pad_indices =
      state.pad_stem_map
      |> Enum.filter(fn {_pad, stem} -> stem == stem_index end)
      |> Enum.map(fn {pad, _stem} -> pad end)

    # Send LED update to all connected MPC devices
    for {port_id, model} <- state.mpc_devices,
        pad_index <- pad_indices do
      sysex_bytes = MPC.pad_color(model, pad_index, color)

      case Output.send_sysex(port_id, sysex_bytes) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "MPCController LED update failed for port #{port_id}, " <>
              "pad #{pad_index}: #{inspect(reason)}"
          )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private: Device Discovery
  # ---------------------------------------------------------------------------

  defp discover_mpc_devices do
    DeviceManager.list_devices()
    |> Enum.reduce(%{}, fn device, acc ->
      case MPC.detect(device.name) do
        {:ok, model} -> Map.put(acc, device.port_id, model)
        :unknown -> acc
      end
    end)
  end
end
