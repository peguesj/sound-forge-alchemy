defmodule SoundForgeWeb.MidiLive do
  @moduledoc """
  LiveView for MIDI device management at /midi.

  Displays connected USB and network MIDI devices with connection status,
  type badges, and real-time activity indicators. Supports enabling/disabling
  MIDI input listening per device and discovering network MIDI sessions.

  Includes a MIDI mapping editor with learn mode for binding MIDI controls
  to application actions, preset loading, and mapping management.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.MIDI.{DeviceManager, Dispatcher, Mapping, Mappings, NetworkDiscovery}
  alias SoundForge.MIDI.Profiles.MPC

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      DeviceManager.subscribe()
    end

    current_user_id = resolve_user_id(socket.assigns[:current_user], session)
    devices = DeviceManager.list_devices()
    network_devices = NetworkDiscovery.list_network_devices()

    mappings =
      if current_user_id, do: Mappings.list_mappings(current_user_id), else: []

    socket =
      socket
      |> assign(:page_title, "MIDI Devices")
      |> assign(:current_user_id, current_user_id)
      |> assign(:devices, devices)
      |> assign(:network_devices, network_devices)
      |> assign(:listening, MapSet.new())
      |> assign(:activity, %{})
      |> assign(:scanning, false)
      |> assign(:mappings, mappings)
      |> assign(:learn_mode, false)
      |> assign(:learn_device, nil)
      |> assign(:selected_action, nil)
      |> assign(:selected_device, nil)
      |> assign(:learned_type, nil)
      |> assign(:learned_channel, nil)
      |> assign(:learned_number, nil)
      |> assign(:selected_preset, nil)
      |> assign(:mapping_flash, nil)

    {:ok, socket}
  end

  # -- Device events (existing) --

  @impl true
  def handle_event("toggle_listen", %{"port-id" => port_id}, socket) do
    listening = socket.assigns.listening

    if MapSet.member?(listening, port_id) do
      Phoenix.PubSub.unsubscribe(SoundForge.PubSub, Dispatcher.topic(port_id))
      {:noreply, assign(socket, :listening, MapSet.delete(listening, port_id))}
    else
      Dispatcher.subscribe(port_id)
      {:noreply, assign(socket, :listening, MapSet.put(listening, port_id))}
    end
  end

  def handle_event("scan_network", _params, socket) do
    NetworkDiscovery.scan_now()
    {:noreply, assign(socket, :scanning, true)}
  end

  # -- Mapping editor events --

  def handle_event("select_action", %{"action" => action}, socket) do
    action_atom = if action == "", do: nil, else: String.to_existing_atom(action)
    {:noreply, assign(socket, :selected_action, action_atom)}
  end

  def handle_event("select_device", %{"device" => device_name}, socket) do
    device_name = if device_name == "", do: nil, else: device_name
    {:noreply, assign(socket, :selected_device, device_name)}
  end

  def handle_event("start_learn", _params, socket) do
    device_name = socket.assigns.selected_device

    if device_name do
      device = Enum.find(socket.assigns.devices, &(&1.name == device_name))

      if device do
        Dispatcher.subscribe(device.port_id)

        socket =
          socket
          |> assign(:learn_mode, true)
          |> assign(:learn_device, device.port_id)
          |> assign(:learned_type, nil)
          |> assign(:learned_channel, nil)
          |> assign(:learned_number, nil)

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_learn", _params, socket) do
    if socket.assigns.learn_device do
      Phoenix.PubSub.unsubscribe(
        SoundForge.PubSub,
        Dispatcher.topic(socket.assigns.learn_device)
      )
    end

    socket =
      socket
      |> assign(:learn_mode, false)
      |> assign(:learn_device, nil)

    {:noreply, socket}
  end

  def handle_event("save_mapping", _params, socket) do
    user_id = socket.assigns.current_user_id
    device_name = socket.assigns.selected_device
    action = socket.assigns.selected_action
    midi_type = socket.assigns.learned_type
    channel = socket.assigns.learned_channel
    number = socket.assigns.learned_number

    if user_id && device_name && action && midi_type && channel != nil && number != nil do
      attrs = %{
        user_id: user_id,
        device_name: device_name,
        midi_type: midi_type,
        channel: channel,
        number: number,
        action: action,
        params: %{}
      }

      case Mappings.create_mapping(attrs) do
        {:ok, _mapping} ->
          mappings = Mappings.list_mappings(user_id)

          socket =
            socket
            |> assign(:mappings, mappings)
            |> assign(:learned_type, nil)
            |> assign(:learned_channel, nil)
            |> assign(:learned_number, nil)
            |> assign(:selected_action, nil)
            |> assign(:mapping_flash, "Mapping saved.")

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, assign(socket, :mapping_flash, "Failed to save mapping.")}
      end
    else
      {:noreply, assign(socket, :mapping_flash, "Please fill all fields before saving.")}
    end
  end

  def handle_event("delete_mapping", %{"id" => id}, socket) do
    user_id = socket.assigns.current_user_id

    case SoundForge.Repo.get(Mapping, id) do
      %Mapping{user_id: ^user_id} = mapping ->
        case Mappings.delete_mapping(mapping) do
          {:ok, _} ->
            mappings = Mappings.list_mappings(user_id)
            {:noreply, assign(socket, :mappings, mappings)}

          {:error, _} ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("load_preset", %{"preset" => preset}, socket) do
    user_id = socket.assigns.current_user_id

    unless user_id do
      {:noreply, assign(socket, :mapping_flash, "No user session.")}
    else
      results = load_preset_mappings(preset, user_id, socket)

      case results do
        {:error, msg} ->
          {:noreply, assign(socket, :mapping_flash, msg)}

        _ ->
          mappings = Mappings.list_mappings(user_id)

          socket =
            socket
            |> assign(:mappings, mappings)
            |> assign(:selected_preset, preset)
            |> assign(:mapping_flash, "Preset '#{preset}' loaded.")

          {:noreply, socket}
      end
    end
  end

  # -- PubSub handlers --

  @impl true
  def handle_info({:midi_device_connected, device}, socket) do
    devices =
      socket.assigns.devices
      |> Enum.reject(&(&1.port_id == device.port_id))
      |> then(&[device | &1])

    {:noreply, assign(socket, :devices, devices)}
  end

  def handle_info({:midi_device_disconnected, device}, socket) do
    devices = Enum.reject(socket.assigns.devices, &(&1.port_id == device.port_id))
    {:noreply, assign(socket, :devices, devices)}
  end

  def handle_info({:network_device_appeared, device}, socket) do
    network_devices =
      socket.assigns.network_devices
      |> Enum.reject(&(&1.id == device.id))
      |> then(&[device | &1])

    {:noreply, assign(socket, :network_devices, network_devices) |> assign(:scanning, false)}
  end

  def handle_info({:network_device_disappeared, device}, socket) do
    network_devices = Enum.reject(socket.assigns.network_devices, &(&1.id == device.id))
    {:noreply, assign(socket, :network_devices, network_devices)}
  end

  def handle_info({:midi_message, port_id, message}, socket) do
    if socket.assigns.learn_mode && socket.assigns.learn_device == port_id do
      {midi_type, channel, number} = extract_mapping_from_message(message)

      if midi_type do
        Phoenix.PubSub.unsubscribe(SoundForge.PubSub, Dispatcher.topic(port_id))

        socket =
          socket
          |> assign(:learn_mode, false)
          |> assign(:learn_device, nil)
          |> assign(:learned_type, midi_type)
          |> assign(:learned_channel, channel)
          |> assign(:learned_number, number)

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      activity = Map.put(socket.assigns.activity, port_id, System.monotonic_time(:millisecond))
      Process.send_after(self(), {:clear_activity, port_id}, 300)
      {:noreply, assign(socket, :activity, activity)}
    end
  end

  def handle_info({:clear_activity, port_id}, socket) do
    now = System.monotonic_time(:millisecond)

    activity =
      case Map.get(socket.assigns.activity, port_id) do
        ts when is_integer(ts) and now - ts >= 280 ->
          Map.delete(socket.assigns.activity, port_id)

        _ ->
          socket.assigns.activity
      end

    {:noreply, assign(socket, :activity, activity)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # -- Render --

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6 space-y-8">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-white">MIDI Devices</h1>
        <div class="badge badge-lg badge-primary">{device_count(@devices, @network_devices)} devices</div>
      </div>

      <%!-- USB / Local Devices --%>
      <div class="space-y-4">
        <h2 class="text-lg font-semibold text-gray-300">Connected Devices</h2>

        <div :if={@devices == []} class="text-gray-500 italic text-sm">
          No MIDI devices connected.
        </div>

        <div
          :for={device <- @devices}
          class="card bg-base-200 shadow-md"
        >
          <div class="card-body flex-row items-center gap-4 p-4">
            <div class={[
              "w-3 h-3 rounded-full flex-shrink-0",
              if(Map.has_key?(@activity, device.port_id),
                do: "bg-green-400 animate-pulse",
                else: "bg-gray-600"
              )
            ]} />

            <div class="flex-1 min-w-0">
              <p class="font-medium text-white truncate">{device.name}</p>
              <p class="text-xs text-gray-400">Port: {device.port_id}</p>
            </div>

            <div class="flex items-center gap-2 flex-shrink-0">
              <span class={type_badge_class(device.type)}>{type_label(device.type)}</span>
              <span class={direction_badge_class(device.direction)}>{direction_label(device.direction)}</span>
              <span class={status_badge_class(device.status)}>{status_label(device.status)}</span>
            </div>

            <div
              :if={device.direction in [:input, :duplex]}
              class="flex items-center gap-2 flex-shrink-0"
            >
              <span class="text-xs text-gray-400">Listen</span>
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-primary"
                checked={MapSet.member?(@listening, device.port_id)}
                phx-click="toggle_listen"
                phx-value-port-id={device.port_id}
              />
            </div>
          </div>
        </div>
      </div>

      <%!-- Network MIDI --%>
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold text-gray-300">Network MIDI Sessions</h2>
          <button
            class={["btn btn-sm btn-outline", @scanning && "loading"]}
            phx-click="scan_network"
            disabled={@scanning}
          >
            Scan Network
          </button>
        </div>

        <div :if={@network_devices == []} class="text-gray-500 italic text-sm">
          No network MIDI sessions discovered.
        </div>

        <div
          :for={net_dev <- @network_devices}
          class="card bg-base-200 shadow-md"
        >
          <div class="card-body flex-row items-center gap-4 p-4">
            <div class="w-3 h-3 rounded-full flex-shrink-0 bg-blue-400" />

            <div class="flex-1 min-w-0">
              <p class="font-medium text-white truncate">{net_dev.name}</p>
              <p class="text-xs text-gray-400">
                {Map.get(net_dev, :host, "unknown")}:{Map.get(net_dev, :port, "?")}
              </p>
            </div>

            <span class="badge badge-info badge-sm">Network</span>
            <span class={status_badge_class(net_dev.status)}>{status_label(net_dev.status)}</span>
          </div>
        </div>
      </div>

      <%!-- MIDI Mapping Editor --%>
      <div class="space-y-4">
        <h2 class="text-lg font-semibold text-gray-300">MIDI Mapping Editor</h2>

        <div :if={@mapping_flash} class="alert alert-info text-sm">
          {@mapping_flash}
        </div>

        <%!-- Preset Selector --%>
        <div class="flex items-center gap-3">
          <label class="text-sm text-gray-400">Load Preset:</label>
          <button class="btn btn-sm btn-outline" phx-click="load_preset" phx-value-preset="generic">
            Generic
          </button>
          <button class="btn btn-sm btn-outline" phx-click="load_preset" phx-value-preset="mpc">
            MPC
          </button>
        </div>

        <%!-- Mapping Form --%>
        <div class="card bg-base-200 shadow-md">
          <div class="card-body p-4 space-y-4">
            <h3 class="font-medium text-white">New Mapping</h3>

            <div class="flex flex-wrap items-end gap-4">
              <%!-- Device dropdown --%>
              <div class="form-control">
                <label class="label"><span class="label-text text-gray-400">Device</span></label>
                <select
                  class="select select-bordered select-sm"
                  phx-change="select_device"
                  name="device"
                >
                  <option value="">Select device...</option>
                  <option
                    :for={device <- @devices}
                    value={device.name}
                    selected={@selected_device == device.name}
                  >
                    {device.name}
                  </option>
                </select>
              </div>

              <%!-- Action dropdown --%>
              <div class="form-control">
                <label class="label"><span class="label-text text-gray-400">Action</span></label>
                <select
                  class="select select-bordered select-sm"
                  phx-change="select_action"
                  name="action"
                >
                  <option value="">Select action...</option>
                  <option
                    :for={action <- Mapping.actions()}
                    value={action}
                    selected={@selected_action == action}
                  >
                    {format_action(action)}
                  </option>
                </select>
              </div>

              <%!-- Learn button --%>
              <div class="form-control">
                <button
                  :if={!@learn_mode}
                  class="btn btn-sm btn-accent"
                  phx-click="start_learn"
                  disabled={is_nil(@selected_device) || is_nil(@selected_action)}
                >
                  Learn
                </button>
                <button
                  :if={@learn_mode}
                  class="btn btn-sm btn-warning animate-pulse"
                  phx-click="cancel_learn"
                >
                  Listening... Cancel
                </button>
              </div>

              <%!-- Learned values display --%>
              <div :if={@learned_type} class="flex items-center gap-2 text-sm text-gray-300">
                <span class="badge badge-ghost badge-sm">{format_midi_type(@learned_type)}</span>
                <span>CH {@learned_channel}</span>
                <span>#{@learned_number}</span>
              </div>

              <%!-- Save button --%>
              <button
                :if={@learned_type && @selected_action && @selected_device}
                class="btn btn-sm btn-primary"
                phx-click="save_mapping"
              >
                Save Mapping
              </button>
            </div>
          </div>
        </div>

        <%!-- Current Mappings Table --%>
        <div :if={@mappings != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th class="text-gray-400">Action</th>
                <th class="text-gray-400">Device</th>
                <th class="text-gray-400">Type</th>
                <th class="text-gray-400">Channel</th>
                <th class="text-gray-400">Number</th>
                <th class="text-gray-400"></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={mapping <- @mappings} class="hover">
                <td class="text-white">{format_action(mapping.action)}</td>
                <td class="text-gray-300">{mapping.device_name}</td>
                <td>
                  <span class="badge badge-ghost badge-sm">{format_midi_type(mapping.midi_type)}</span>
                </td>
                <td class="text-gray-300">{mapping.channel}</td>
                <td class="text-gray-300">{mapping.number}</td>
                <td>
                  <button
                    class="btn btn-ghost btn-xs text-error"
                    phx-click="delete_mapping"
                    phx-value-id={mapping.id}
                  >
                    Delete
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@mappings == []} class="text-gray-500 italic text-sm">
          No mappings configured. Use the editor above or load a preset.
        </div>
      </div>
    </div>
    """
  end

  # -- Private Helpers --

  defp resolve_user_id(%{id: id}, _session) when is_binary(id), do: id

  defp resolve_user_id(_, session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _inserted_at} <- SoundForge.Accounts.get_user_by_session_token(token) do
      user.id
    else
      _ -> nil
    end
  end

  defp extract_mapping_from_message(%{type: :cc, channel: ch, data: data}) do
    {:cc, ch, Map.get(data, :number, Map.get(data, :controller))}
  end

  defp extract_mapping_from_message(%{type: :note_on, channel: ch, data: data}) do
    {:note_on, ch, Map.get(data, :note, Map.get(data, :number))}
  end

  defp extract_mapping_from_message(%{type: :note_off, channel: ch, data: data}) do
    {:note_off, ch, Map.get(data, :note, Map.get(data, :number))}
  end

  defp extract_mapping_from_message(_message), do: {nil, nil, nil}

  defp load_preset_mappings("generic", user_id, _socket) do
    Mappings.insert_default_preset(user_id)
  end

  defp load_preset_mappings("mpc", user_id, socket) do
    model =
      socket.assigns.devices
      |> Enum.find_value(:mpc_one, fn device ->
        case MPC.detect(device.name) do
          {:ok, m} -> m
          :unknown -> nil
        end
      end)

    model
    |> MPC.default_mappings(user_id)
    |> Enum.map(&Mappings.create_mapping/1)
  end

  defp load_preset_mappings(preset, _user_id, _socket) do
    {:error, "Unknown preset: #{preset}"}
  end

  defp format_action(action) do
    action
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_midi_type(:cc), do: "CC"
  defp format_midi_type(:note_on), do: "Note On"
  defp format_midi_type(:note_off), do: "Note Off"
  defp format_midi_type(other), do: Atom.to_string(other)

  defp device_count(devices, network_devices) do
    length(devices) + length(network_devices)
  end

  defp type_label(:usb), do: "USB"
  defp type_label(:network), do: "Network"
  defp type_label(:virtual), do: "Virtual"
  defp type_label(_), do: "Unknown"

  defp type_badge_class(:usb), do: "badge badge-sm badge-warning"
  defp type_badge_class(:network), do: "badge badge-sm badge-info"
  defp type_badge_class(:virtual), do: "badge badge-sm badge-secondary"
  defp type_badge_class(_), do: "badge badge-sm badge-ghost"

  defp direction_label(:input), do: "In"
  defp direction_label(:output), do: "Out"
  defp direction_label(:duplex), do: "Both"
  defp direction_label(_), do: "?"

  defp direction_badge_class(:input), do: "badge badge-sm badge-accent"
  defp direction_badge_class(:output), do: "badge badge-sm badge-neutral"
  defp direction_badge_class(:duplex), do: "badge badge-sm badge-primary"
  defp direction_badge_class(_), do: "badge badge-sm badge-ghost"

  defp status_label(:connected), do: "Connected"
  defp status_label(:disconnected), do: "Disconnected"
  defp status_label(:available), do: "Available"
  defp status_label(_), do: "Unknown"

  defp status_badge_class(:connected), do: "badge badge-sm badge-success"
  defp status_badge_class(:available), do: "badge badge-sm badge-success"
  defp status_badge_class(:disconnected), do: "badge badge-sm badge-error"
  defp status_badge_class(_), do: "badge badge-sm badge-ghost"
end
