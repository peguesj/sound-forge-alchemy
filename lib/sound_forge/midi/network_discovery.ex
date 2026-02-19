defmodule SoundForge.MIDI.NetworkDiscovery do
  @moduledoc """
  Discovers network MIDI sessions advertised via mDNS/Bonjour.

  Uses the macOS built-in `dns-sd` tool to browse for `_apple-midi._udp`
  services on the local network. Discovered devices are merged into the
  `:midi_devices` ETS table (owned by `SoundForge.MIDI.DeviceManager`)
  with `type: :network`.

  Broadcasts on `SoundForge.PubSub` topic `"midi:devices"` when network
  devices appear or disappear.

  ## Configuration

      config :sound_forge, SoundForge.MIDI.NetworkDiscovery,
        scan_interval: 10_000,
        scan_timeout: 5_000,
        enabled: true

  """

  use GenServer

  require Logger

  @default_scan_interval 10_000
  @default_scan_timeout 5_000
  @ets_table :midi_devices
  @pubsub SoundForge.PubSub
  @topic "midi:devices"
  @service_type "_apple-midi._udp"

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc "Starts the NetworkDiscovery GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the list of currently known network MIDI devices."
  @spec list_network_devices() :: [map()]
  def list_network_devices do
    if ets_table_exists?() do
      :ets.match_object(@ets_table, {:_, %{type: :network}})
      |> Enum.map(fn {_key, device} -> device end)
    else
      []
    end
  end

  @doc "Triggers an immediate network scan."
  @spec scan_now() :: :ok
  def scan_now do
    GenServer.cast(__MODULE__, :scan_now)
  end

  # -------------------------------------------------------------------
  # GenServer Callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    config = Application.get_env(:sound_forge, __MODULE__, [])
    merged = Keyword.merge(config, opts)

    state = %{
      scan_interval: Keyword.get(merged, :scan_interval, @default_scan_interval),
      scan_timeout: Keyword.get(merged, :scan_timeout, @default_scan_timeout),
      enabled: Keyword.get(merged, :enabled, true),
      known_devices: %{}
    }

    if state.enabled do
      schedule_scan(0)
    end

    {:ok, state}
  end

  @impl true
  def handle_cast(:scan_now, state) do
    {:noreply, do_scan(state)}
  end

  @impl true
  def handle_info(:scan, state) do
    new_state = do_scan(state)
    schedule_scan(new_state.scan_interval)
    {:noreply, new_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -------------------------------------------------------------------
  # Internal
  # -------------------------------------------------------------------

  defp do_scan(state) do
    discovered =
      try do
        browse_mdns(state.scan_timeout)
      rescue
        e ->
          Logger.warning("NetworkDiscovery scan failed: #{inspect(e)}")
          %{}
      end

    previous = state.known_devices

    appeared = Map.drop(discovered, Map.keys(previous))
    disappeared = Map.drop(previous, Map.keys(discovered))

    if ets_table_exists?() do
      Enum.each(appeared, fn {key, device} ->
        :ets.insert(@ets_table, {key, device})
      end)

      Enum.each(disappeared, fn {key, _device} ->
        :ets.delete(@ets_table, key)
      end)

      # Update entries whose metadata may have changed
      Enum.each(discovered, fn {key, device} ->
        case Map.get(previous, key) do
          ^device -> :ok
          _other -> :ets.insert(@ets_table, {key, device})
        end
      end)
    else
      Logger.debug("NetworkDiscovery: ETS table #{@ets_table} not available yet")
    end

    Enum.each(appeared, fn {_key, device} ->
      Phoenix.PubSub.broadcast(@pubsub, @topic, {:network_device_appeared, device})
    end)

    Enum.each(disappeared, fn {_key, device} ->
      Phoenix.PubSub.broadcast(@pubsub, @topic, {:network_device_disappeared, device})
    end)

    if map_size(appeared) > 0 or map_size(disappeared) > 0 do
      Logger.info(
        "NetworkDiscovery: +#{map_size(appeared)} -#{map_size(disappeared)} network MIDI devices " <>
          "(total: #{map_size(discovered)})"
      )
    end

    %{state | known_devices: discovered}
  end

  @spec browse_mdns(non_neg_integer()) :: %{String.t() => map()}
  defp browse_mdns(timeout) do
    case System.find_executable("dns-sd") do
      nil ->
        Logger.warning("NetworkDiscovery: dns-sd not found, skipping scan")
        %{}

      dns_sd_path ->
        run_dns_sd_browse(dns_sd_path, timeout)
    end
  end

  defp run_dns_sd_browse(dns_sd_path, timeout) do
    port =
      Port.open({:spawn_executable, dns_sd_path}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["-B", @service_type]
      ])

    output = collect_output(port, timeout, [])

    services = parse_browse_output(output)
    resolve_services(services, dns_sd_path, min(timeout, 3_000))
  end

  defp collect_output(port, timeout, acc) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, timeout, [data | acc])

      {^port, {:exit_status, _}} ->
        IO.iodata_to_binary(Enum.reverse(acc))
    after
      timeout ->
        try do
          Port.close(port)
        rescue
          _ -> :ok
        catch
          _, _ -> :ok
        end

        IO.iodata_to_binary(Enum.reverse(acc))
    end
  end

  defp parse_browse_output(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "Add"))
    |> Enum.map(&parse_browse_line/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_browse_line(line) do
    # dns-sd -B output columns (whitespace-separated):
    # Timestamp  A/R  Flags  if  Domain  ServiceType  InstanceName
    case Regex.run(~r/Add\s+\d+\s+\d+\s+(\S+)\s+\S+\s+(.+)$/, line) do
      [_, domain, name] -> {String.trim(name), String.trim(domain)}
      _ -> nil
    end
  end

  defp resolve_services(services, dns_sd_path, timeout) do
    services
    |> Enum.map(fn {instance_name, domain} ->
      Task.async(fn -> resolve_service(dns_sd_path, instance_name, domain, timeout) end)
    end)
    |> Task.yield_many(timeout + 1_000)
    |> Enum.map(fn {task, result} ->
      case result do
        {:ok, device} ->
          device

        nil ->
          Task.shutdown(task, :brutal_kill)
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn device -> {device.id, device} end)
  end

  defp resolve_service(dns_sd_path, instance_name, domain, timeout) do
    port =
      Port.open({:spawn_executable, dns_sd_path}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["-L", instance_name, @service_type, domain]
      ])

    output = collect_output(port, timeout, [])
    parse_resolve_output(output, instance_name)
  end

  defp parse_resolve_output(output, instance_name) do
    # dns-sd -L output: "... can be reached at host.local.:5004 ..."
    case Regex.run(~r/can be reached at\s+(\S+?):(\d+)/, output) do
      [_, host, port_str] ->
        %{
          id: network_device_id(instance_name),
          name: instance_name,
          type: :network,
          status: :available,
          host: String.trim_trailing(host, "."),
          port: String.to_integer(port_str),
          session_name: instance_name,
          discovered_at: DateTime.utc_now()
        }

      _ ->
        nil
    end
  end

  defp network_device_id(instance_name) do
    hash = :crypto.hash(:md5, instance_name) |> Base.encode16(case: :lower)
    "network:#{hash}"
  end

  defp ets_table_exists? do
    :ets.whereis(@ets_table) != :undefined
  end

  defp schedule_scan(delay) do
    Process.send_after(self(), :scan, delay)
  end
end
