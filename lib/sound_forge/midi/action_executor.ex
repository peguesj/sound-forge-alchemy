defmodule SoundForge.MIDI.ActionExecutor do
  @moduledoc """
  GenServer that receives parsed MIDI messages, looks up the mapping for the
  source device, and executes the mapped action.

  Subscribes to `"midi:messages:{port_id}"` topics for all connected devices
  and re-subscribes when new devices connect. Incoming messages are matched
  against `SoundForge.MIDI.Mappings` for the source device. Matched actions
  are dispatched and state changes broadcast on PubSub for LiveView reactivity.

  ## PubSub Topics

    - Subscribes to: `"midi:messages:{port_id}"` (per device), `"midi:devices"` (hotplug)
    - Publishes to: `"midi:actions"` (all action events), `"track_playback:{track_id}"` (volume/state)

  ## Supported Actions

    - `:play` / `:stop` - track transport controls
    - `:stem_solo` / `:stem_mute` - toggle stem solo/mute state
    - `:stem_volume` - CC value (0-127) mapped to 0.0-1.0 float
    - `:seek` - seek within current track
    - `:next_track` / `:prev_track` - track navigation
  """

  use GenServer

  require Logger

  alias SoundForge.MIDI.{DeviceManager, Mappings}

  @pubsub SoundForge.PubSub
  @actions_topic "midi:actions"

  # -- Public API --

  @doc """
  Starts the ActionExecutor GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribes the calling process to action execution events.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @actions_topic)
  end

  # -- GenServer Callbacks --

  @impl true
  def init(opts) do
    user_id = Keyword.get(opts, :user_id)

    # Subscribe to device hotplug events
    DeviceManager.subscribe()

    # Subscribe to MIDI messages for all currently connected devices
    devices = DeviceManager.list_devices()
    device_map = subscribe_to_devices(devices)

    state = %{
      user_id: user_id,
      devices: device_map,
      solo_states: %{},
      mute_states: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:midi_device_connected, device}, state) do
    port_id = device.port_id
    topic = midi_messages_topic(port_id)
    Phoenix.PubSub.subscribe(@pubsub, topic)

    device_map = Map.put(state.devices, port_id, device)
    {:noreply, %{state | devices: device_map}}
  end

  def handle_info({:midi_device_disconnected, device}, state) do
    port_id = device.port_id
    topic = midi_messages_topic(port_id)
    Phoenix.PubSub.unsubscribe(@pubsub, topic)

    device_map = Map.delete(state.devices, port_id)
    {:noreply, %{state | devices: device_map}}
  end

  def handle_info({:midi_message, port_id, message}, state) do
    state = handle_midi_message(port_id, message, state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -- Private Helpers --

  defp subscribe_to_devices(devices) do
    Enum.reduce(devices, %{}, fn device, acc ->
      topic = midi_messages_topic(device.port_id)
      Phoenix.PubSub.subscribe(@pubsub, topic)
      Map.put(acc, device.port_id, device)
    end)
  end

  defp midi_messages_topic(port_id), do: "midi:messages:#{port_id}"

  defp handle_midi_message(port_id, message, state) do
    device = Map.get(state.devices, port_id)

    if device && state.user_id do
      case find_mapping(state.user_id, device.name, message) do
        nil ->
          state

        mapping ->
          execute_action(mapping, message, state)
      end
    else
      state
    end
  end

  defp find_mapping(user_id, device_name, message) do
    number = extract_number(message)

    if number do
      user_id
      |> Mappings.get_mappings_for_device(device_name)
      |> Enum.find(fn m ->
        m.midi_type == message.type &&
          m.channel == message.channel &&
          m.number == number
      end)
    end
  end

  defp extract_number(%{type: :cc, data: %{controller: controller}}), do: controller

  defp extract_number(%{type: type, data: %{note: note}})
       when type in [:note_on, :note_off],
       do: note

  defp extract_number(_), do: nil

  defp execute_action(mapping, message, state) do
    action = mapping.action
    params = mapping.params || %{}

    case action do
      :play ->
        broadcast_action(:play, params)
        state

      :stop ->
        broadcast_action(:stop, params)
        state

      :next_track ->
        broadcast_action(:next_track, params)
        state

      :prev_track ->
        broadcast_action(:prev_track, params)
        state

      :seek ->
        broadcast_action(:seek, params)
        state

      :stem_volume ->
        handle_stem_volume(message, params, state)

      :stem_solo ->
        handle_stem_solo(params, state)

      :stem_mute ->
        handle_stem_mute(params, state)

      :bpm_tap ->
        broadcast_action(:bpm_tap, params)
        state

      _ ->
        state
    end
  end

  defp handle_stem_volume(message, params, state) do
    value = extract_cc_value(message)
    volume = cc_to_float(value)
    track_id = Map.get(params, "track_id")
    target = Map.get(params, "target", "master")

    event = %{action: :stem_volume, volume: volume, target: target, track_id: track_id}
    broadcast_action(:stem_volume, event)

    if track_id do
      Phoenix.PubSub.broadcast(
        @pubsub,
        "track_playback:#{track_id}",
        {:stem_volume_changed, %{volume: volume, target: target}}
      )
    end

    state
  end

  defp handle_stem_solo(params, state) do
    track_id = Map.get(params, "track_id")
    stem = Map.get(params, "stem")
    key = {track_id, stem}

    current = Map.get(state.solo_states, key, false)
    new_val = !current
    solo_states = Map.put(state.solo_states, key, new_val)

    event = %{action: :stem_solo, track_id: track_id, stem: stem, soloed: new_val}
    broadcast_action(:stem_solo, event)

    if track_id do
      Phoenix.PubSub.broadcast(
        @pubsub,
        "track_playback:#{track_id}",
        {:stem_solo_changed, %{stem: stem, soloed: new_val}}
      )
    end

    %{state | solo_states: solo_states}
  end

  defp handle_stem_mute(params, state) do
    track_id = Map.get(params, "track_id")
    stem = Map.get(params, "stem")
    key = {track_id, stem}

    current = Map.get(state.mute_states, key, false)
    new_val = !current
    mute_states = Map.put(state.mute_states, key, new_val)

    event = %{action: :stem_mute, track_id: track_id, stem: stem, muted: new_val}
    broadcast_action(:stem_mute, event)

    if track_id do
      Phoenix.PubSub.broadcast(
        @pubsub,
        "track_playback:#{track_id}",
        {:stem_mute_changed, %{stem: stem, muted: new_val}}
      )
    end

    %{state | mute_states: mute_states}
  end

  defp extract_cc_value(%{data: %{value: value}}), do: value
  defp extract_cc_value(%{data: %{velocity: velocity}}), do: velocity
  defp extract_cc_value(_), do: 0

  @doc false
  @spec cc_to_float(integer()) :: float()
  def cc_to_float(value) when is_integer(value) and value >= 0 and value <= 127 do
    Float.round(value / 127.0, 4)
  end

  def cc_to_float(value) when is_integer(value) and value > 127, do: 1.0
  def cc_to_float(_), do: 0.0

  defp broadcast_action(action, params) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      @actions_topic,
      {:midi_action, action, params}
    )
  end
end
