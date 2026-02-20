defmodule SoundForge.MIDI.Dispatcher do
  @moduledoc """
  GenServer that listens on MIDI input ports and broadcasts parsed messages
  on `"midi:messages:{port_id}"` PubSub topics.

  Subscribes to `SoundForge.MIDI.DeviceManager` for device connect/disconnect
  events and automatically subscribes to or unsubscribes from input ports.
  All Midiex calls are wrapped in try/rescue for resilience.

  Messages from Midiex arrive as `%Midiex.MidiMessage{}` structs with raw
  byte data, which are parsed via `SoundForge.MIDI.Parser` and broadcast
  as `{:midi_message, port_id, %SoundForge.MIDI.Message{}}`.
  """

  use GenServer

  require Logger

  alias SoundForge.MIDI.{DeviceManager, Parser}

  @pubsub SoundForge.PubSub

  # -- Public API --

  @doc """
  Starts the Dispatcher GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribes the calling process to parsed MIDI messages for the given port.
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(port_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(port_id))
  end

  @doc """
  Returns the PubSub topic for a given port.
  """
  @spec topic(String.t()) :: String.t()
  def topic(port_id), do: "midi:messages:#{port_id}"

  # -- GenServer Callbacks --

  @impl true
  def init(_opts) do
    DeviceManager.subscribe()
    subscribed = subscribe_existing_inputs()
    {:ok, %{subscribed: subscribed}}
  end

  @impl true
  def handle_info({:midi_device_connected, device}, state) do
    if device.direction in [:input, :duplex] do
      case subscribe_port(device.port_id) do
        {:ok, port_struct} ->
          {:noreply, put_in(state, [:subscribed, device.port_id], port_struct)}

        :error ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:midi_device_disconnected, device}, state) do
    state = unsubscribe_and_remove(state, device.port_id)
    {:noreply, state}
  end

  # Midiex delivers messages as %Midiex.MidiMessage{port: port_struct, data: [bytes], timestamp: ts}
  def handle_info(%{__struct__: Midiex.MidiMessage, data: data, port: port} = _midi_msg, state) do
    port_id = extract_port_id(port)
    raw_bytes = :erlang.list_to_binary(data)
    messages = Parser.parse(raw_bytes)

    for msg <- messages do
      Phoenix.PubSub.broadcast(@pubsub, topic(port_id), {:midi_message, port_id, msg})
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    for {_port_id, port_struct} <- state.subscribed do
      unsubscribe_port(port_struct)
    end

    :ok
  end

  # -- Private Helpers --

  defp subscribe_existing_inputs do
    DeviceManager.list_devices()
    |> Enum.filter(&(&1.direction in [:input, :duplex]))
    |> Enum.reduce(%{}, fn device, acc ->
      case subscribe_port(device.port_id) do
        {:ok, port_struct} -> Map.put(acc, device.port_id, port_struct)
        :error -> acc
      end
    end)
  end

  defp subscribe_port(port_id) do
    try do
      port_struct = find_midiex_port(port_id)

      if port_struct do
        Midiex.subscribe(port_struct)
        Logger.info("MIDI Dispatcher subscribed to input port #{port_id}")
        {:ok, port_struct}
      else
        Logger.warning("MIDI Dispatcher could not find Midiex port for #{port_id}")
        :error
      end
    rescue
      e ->
        Logger.warning(
          "MIDI Dispatcher failed to subscribe to port #{port_id}: #{Exception.message(e)}"
        )

        :error
    end
  end

  defp unsubscribe_port(port_struct) do
    try do
      Midiex.unsubscribe(port_struct)
    rescue
      e ->
        Logger.warning("MIDI Dispatcher failed to unsubscribe: #{Exception.message(e)}")
    end
  end

  defp unsubscribe_and_remove(state, port_id) do
    case Map.get(state.subscribed, port_id) do
      nil ->
        state

      port_struct ->
        unsubscribe_port(port_struct)
        update_in(state, [:subscribed], &Map.delete(&1, port_id))
    end
  end

  defp find_midiex_port(port_id) do
    try do
      Midiex.ports(:input)
      |> List.wrap()
      |> Enum.find(fn port ->
        to_string(Map.get(port, :num, "")) == to_string(port_id) or
          to_string(Map.get(port, :port_id, "")) == to_string(port_id)
      end)
    rescue
      _e -> nil
    end
  end

  defp extract_port_id(port) when is_map(port) do
    to_string(Map.get(port, :num, Map.get(port, :port_id, "")))
  end

  defp extract_port_id(port), do: to_string(port)
end
