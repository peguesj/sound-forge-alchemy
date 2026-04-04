defmodule SoundForge.MIDI.DeviceManager do
  @moduledoc """
  GenServer that discovers and tracks connected USB MIDI devices.

  Maintains an ETS table (`:midi_devices`) of connected devices and polls
  for hotplug events every 5 seconds via `Midiex.hotplug/0`. Broadcasts
  device connect/disconnect events on the `"midi:devices"` PubSub topic.

  ## ETS Schema

  Each entry is keyed by `port_id` and stores:

      %{
        port_id: String.t(),
        name: String.t(),
        direction: :input | :output | :duplex,
        type: :usb | :virtual | :unknown,
        status: :connected | :disconnected,
        connected_at: DateTime.t()
      }

  ## PubSub Events

  Subscribers to `"midi:devices"` receive:

    - `{:midi_device_connected, device}` - a new device was detected
    - `{:midi_device_disconnected, device}` - a previously connected device was removed
  """

  use GenServer

  require Logger

  @table :midi_devices
  @poll_interval_ms 5_000
  @pubsub_topic "midi:devices"

  # -- Public API --

  @doc """
  Starts the DeviceManager GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns all connected MIDI devices.
  """
  @spec list_devices() :: [map()]
  def list_devices do
    if :ets.whereis(@table) != :undefined do
      @table
      |> :ets.tab2list()
      |> Enum.map(fn {_port_id, device} -> device end)
    else
      []
    end
  end

  @doc "Look up a single device by port_id. Returns the device map or nil."
  def get_device_by_port(port_id) do
    if :ets.whereis(@table) != :undefined do
      case :ets.lookup(@table, port_id) do
        [{^port_id, device}] -> device
        _ -> nil
      end
    end
  end

  @doc """
  Subscribes the calling process to MIDI device events.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(SoundForge.PubSub, @pubsub_topic)
  end

  # -- GenServer Callbacks --

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    devices =
      try do
        discover_devices()
      rescue
        e ->
          Logger.warning(
            "MIDI device discovery failed during init (no hardware?): #{inspect(e)}"
          )

          []
      catch
        kind, reason ->
          Logger.warning(
            "MIDI NIF init error (#{kind}): #{inspect(reason)} -- " <>
              "running without MIDI hardware support"
          )

          []
      end

    Logger.info("MIDI DeviceManager: discovered #{length(devices)} device(s) at startup")
    store_devices(devices)

    schedule_poll()

    {:ok, %{table: table, midi_available: devices != []}}
  end

  @impl true
  def handle_info(:poll_hotplug, state) do
    poll_hotplug()
    schedule_poll()
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -- Private Helpers --

  defp schedule_poll do
    Process.send_after(self(), :poll_hotplug, @poll_interval_ms)
  end

  defp poll_hotplug do
    # If discover returns empty the NIF may be temporarily unavailable; skip diff
    # to avoid falsely evicting valid ETS entries.
    case discover_devices() do
      [] ->
        :ok

      current_devices ->
        current_ids = MapSet.new(current_devices, & &1.port_id)

        previous_ids =
          if :ets.whereis(@table) != :undefined do
            @table
            |> :ets.tab2list()
            |> Enum.map(fn {port_id, _} -> port_id end)
            |> MapSet.new()
          else
            MapSet.new()
          end

        # Detect new devices
        new_ids = MapSet.difference(current_ids, previous_ids)

        for device <- current_devices, MapSet.member?(new_ids, device.port_id) do
          :ets.insert(@table, {device.port_id, device})
          broadcast({:midi_device_connected, device})
        end

        # Detect removed devices
        removed_ids = MapSet.difference(previous_ids, current_ids)

        for removed_id <- removed_ids do
          case :ets.lookup(@table, removed_id) do
            [{^removed_id, device}] ->
              disconnected = %{device | status: :disconnected}
              :ets.delete(@table, removed_id)
              broadcast({:midi_device_disconnected, disconnected})

            [] ->
              :ok
          end
        end
    end
  end

  defp discover_devices do
    try do
      Midiex.ports()
      |> List.wrap()
      |> Enum.map(&port_to_device/1)
    rescue
      e ->
        Logger.warning("Midiex.ports/0 raised: #{inspect(e)}")
        []
    catch
      kind, reason ->
        Logger.warning("Midiex.ports/0 NIF threw (#{kind}): #{inspect(reason)}")
        []
    end
  end

  defp port_to_device(port) do
    direction = parse_direction(port)
    num = to_string(Map.get(port, :port_id) || Map.get(port, :num, ""))

    %{
      # Composite key prevents input/output ports from colliding in ETS when
      # they share the same numeric index (common on macOS Core MIDI).
      port_id: "#{direction}:#{num}",
      name: to_string(Map.get(port, :name, "Unknown")),
      direction: direction,
      type: parse_type(port),
      status: :connected,
      connected_at: DateTime.utc_now()
    }
  end

  defp parse_direction(%{direction: :input}), do: :input
  defp parse_direction(%{direction: :output}), do: :output
  defp parse_direction(%{direction: :duplex}), do: :duplex
  defp parse_direction(%{is_input: true, is_output: true}), do: :duplex
  defp parse_direction(%{is_input: true}), do: :input
  defp parse_direction(%{is_output: true}), do: :output
  defp parse_direction(_), do: :input

  defp parse_type(%{name: name}) when is_binary(name) do
    downcased = String.downcase(name)

    cond do
      String.contains?(downcased, "usb") -> :usb
      String.contains?(downcased, "virtual") -> :virtual
      true -> :unknown
    end
  end

  defp parse_type(_), do: :unknown

  defp store_devices(devices) do
    for device <- devices do
      :ets.insert(@table, {device.port_id, device})
    end
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(SoundForge.PubSub, @pubsub_topic, message)
  end
end
