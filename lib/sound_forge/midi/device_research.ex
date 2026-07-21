defmodule SoundForge.MIDI.DeviceResearch do
  @moduledoc """
  Researches connected MIDI devices that are not in the ControllerRegistry.

  On device connect, queries macOS `ioreg` for USB vendor/product IDs,
  looks up the manufacturer, and broadcasts enriched device info on the
  `"midi:devices"` PubSub topic as `{:midi_device_researched, info}`.

  Results are cached in ETS (`:midi_device_research`) to avoid repeated
  lookups for the same port_id.
  """

  use GenServer
  require Logger

  alias SoundForge.MIDI.ControllerRegistry

  @table :midi_device_research
  @pubsub SoundForge.PubSub
  @topic "midi:devices"

  # Known USB MIDI vendor IDs → manufacturer names
  @vendor_names %{
    "0x09E8" => "AKAI Professional",
    "0x1235" => "Focusrite",
    "0x1410" => "Novation",
    "0x0763" => "M-Audio",
    "0x2982" => "Arturia",
    "0x1BCF" => "Roland",
    "0x0582" => "Roland",
    "0x1F38" => "Korg",
    "0x2B4C" => "Nektar",
    "0x17CC" => "Native Instruments",
    "0x2673" => "IK Multimedia",
    "0x1A86" => "Innokin / M-VAVE",
    "0x1E30" => "iRig",
    "0x0499" => "Yamaha",
    "0x0944" => "BEHRINGER",
    "0x1C75" => "Arturia",
    "0x047F" => "Plantronics",
    "0x0D8C" => "C-Media"
  }

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns cached research for a device port_id, or nil."
  def get_info(port_id) do
    if :ets.whereis(@table) != :undefined do
      case :ets.lookup(@table, port_id) do
        [{^port_id, info}] -> info
        _ -> nil
      end
    end
  end

  # --------------------------------------------------------------------------
  # GenServer Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    Phoenix.PubSub.subscribe(@pubsub, @topic)
    {:ok, %{}}
  end

  @impl true
  def handle_info({:midi_device_connected, device}, state) do
    # Skip if already cached or in ControllerRegistry
    unless :ets.whereis(@table) != :undefined and :ets.lookup(@table, device.port_id) != [] do
      Task.start(fn -> research_and_broadcast(device) end)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --------------------------------------------------------------------------
  # Internal
  # --------------------------------------------------------------------------

  defp research_and_broadcast(device) do
    registry_entry = ControllerRegistry.detect(device.name)

    info =
      if registry_entry do
        %{
          port_id: device.port_id,
          device_name: device.name,
          source: :registry,
          manufacturer: registry_entry.manufacturer,
          model: registry_entry.name,
          registry_id: registry_entry.id,
          capabilities: summarize_registry(registry_entry)
        }
      else
        usb_info = query_usb_info(device.name)

        %{
          port_id: device.port_id,
          device_name: device.name,
          source: :researched,
          manufacturer: usb_info[:manufacturer] || extract_manufacturer(device.name),
          model: device.name,
          vendor_id: usb_info[:vendor_id],
          product_id: usb_info[:product_id],
          capabilities: usb_info[:capabilities] || []
        }
      end

    if :ets.whereis(@table) != :undefined do
      :ets.insert(@table, {device.port_id, info})
    end

    Phoenix.PubSub.broadcast(@pubsub, @topic, {:midi_device_researched, info})
    Logger.info("MIDI DeviceResearch: researched #{device.name} → #{inspect(info.manufacturer)}")
  end

  defp query_usb_info(device_name) do
    case System.find_executable("ioreg") do
      nil -> %{}
      ioreg_path -> run_ioreg(ioreg_path, device_name)
    end
  end

  defp run_ioreg(ioreg_path, device_name) do
    case System.cmd(ioreg_path, ["-p", "IOUSB", "-l", "-r", "-c", "IOUSBDevice"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> parse_ioreg_output(output, device_name)
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  defp parse_ioreg_output(output, device_name) do
    name_lower = String.downcase(device_name)

    # Split into device blocks by "+-o" entries
    blocks =
      output
      |> String.split(~r/\+-o/)
      |> Enum.filter(fn block ->
        String.downcase(block) |> String.contains?(name_lower) or
          String.downcase(block) |> String.contains?("midi")
      end)

    Enum.reduce_while(blocks, %{}, fn block, _acc ->
      vendor_id = extract_hex(block, ~r/"idVendor" = (0x[0-9A-Fa-f]+|\d+)/)
      product_id = extract_hex(block, ~r/"idProduct" = (0x[0-9A-Fa-f]+|\d+)/)

      if vendor_id do
        vendor_hex = to_hex_string(vendor_id)
        manufacturer = Map.get(@vendor_names, String.upcase(vendor_hex), nil)

        {:halt,
         %{
           vendor_id: vendor_hex,
           product_id: product_id && to_hex_string(product_id),
           manufacturer: manufacturer,
           capabilities: infer_capabilities(block)
         }}
      else
        {:cont, %{}}
      end
    end)
  end

  defp extract_hex(text, pattern) do
    case Regex.run(pattern, text) do
      [_, hex_or_int] ->
        if String.starts_with?(hex_or_int, "0x") do
          String.to_integer(String.slice(hex_or_int, 2..-1//1), 16)
        else
          String.to_integer(hex_or_int)
        end

      _ ->
        nil
    end
  end

  defp to_hex_string(n) when is_integer(n) do
    "0x" <> (Integer.to_string(n, 16) |> String.upcase() |> String.pad_leading(4, "0"))
  end

  defp infer_capabilities(block) do
    caps = []
    caps = if String.contains?(block, "MIDI"), do: [:midi | caps], else: caps
    caps = if String.contains?(block, "Audio"), do: [:audio | caps], else: caps
    caps
  end

  defp extract_manufacturer(name) do
    # Heuristic: first word of device name is often the manufacturer
    name |> String.split() |> List.first()
  end

  defp summarize_registry(entry) do
    pads = length(entry.pads)
    knobs = length(entry.knobs)
    buttons = length(entry.buttons)
    ["#{pads} pads", "#{knobs} knobs", "#{buttons} buttons"]
  end
end
