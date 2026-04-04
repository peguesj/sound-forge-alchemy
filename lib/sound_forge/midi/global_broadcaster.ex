defmodule SoundForge.MIDI.GlobalBroadcaster do
  @moduledoc """
  GenServer that subscribes to ALL MIDI device messages and rebroadcasts them
  on the `"midi:global_bar"` PubSub topic.

  This allows any LiveView (regardless of which tab or page is active) to
  subscribe to a single topic and receive a rolling stream of MIDI activity
  for the global MIDI bar and monitor overlay.

  Events broadcast on `"midi:global_bar"`:
    `{:midi_global_event, port_id, %SoundForge.MIDI.Message{}}`
  """

  use GenServer

  require Logger

  alias SoundForge.MIDI.{DeviceManager, Dispatcher}

  @pubsub SoundForge.PubSub
  @global_topic "midi:global_bar"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Subscribe to the global MIDI bar topic."
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @global_topic)
  end

  def global_topic, do: @global_topic

  # -- GenServer --

  @impl true
  def init(_opts) do
    DeviceManager.subscribe()
    devices = DeviceManager.list_devices()
    subscribe_to_devices(devices)
    {:ok, %{devices: MapSet.new(Enum.map(devices, & &1.port_id))}}
  end

  @impl true
  def handle_info({:midi_device_connected, device}, state) do
    unless MapSet.member?(state.devices, device.port_id) do
      Phoenix.PubSub.subscribe(@pubsub, Dispatcher.topic(device.port_id))
    end
    {:noreply, %{state | devices: MapSet.put(state.devices, device.port_id)}}
  end

  def handle_info({:midi_device_disconnected, device}, state) do
    {:noreply, %{state | devices: MapSet.delete(state.devices, device.port_id)}}
  end

  @impl true
  def handle_info({:midi_message, port_id, msg}, state) do
    Phoenix.PubSub.broadcast(@pubsub, @global_topic, {:midi_global_event, port_id, msg})
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- Helpers --

  defp subscribe_to_devices(devices) do
    Enum.each(devices, fn device ->
      Phoenix.PubSub.subscribe(@pubsub, Dispatcher.topic(device.port_id))
    end)
  end
end
