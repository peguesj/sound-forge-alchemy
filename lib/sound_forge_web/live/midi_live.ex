defmodule SoundForgeWeb.MidiLive do
  @moduledoc """
  LiveView for MIDI device management at /midi.

  Displays connected USB and network MIDI devices with connection status,
  type badges, and real-time activity indicators. Supports enabling/disabling
  MIDI input listening per device and discovering network MIDI sessions.

  Includes a comprehensive MIDI mapping editor with learn mode, visual controller
  mapping grid, CC/Note heatmaps, MIDI activity monitor, and preset loading.
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
      |> assign(:page_title, "MIDI Settings")
      |> assign(:current_scope, socket.assigns[:current_scope])
      |> assign(:current_user_id, current_user_id)
      |> assign(:nav_tab, :library)
      |> assign(:nav_context, :all_tracks)
      |> assign(:midi_devices, devices)
      |> assign(:midi_bpm, nil)
      |> assign(:midi_transport, :stopped)
      |> assign(:pipelines, %{})
      |> assign(:refreshing_midi, false)
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
      |> assign(:selected_tab, "overview")
      |> assign(:midi_monitor, [])
      |> assign(:monitor_listening, false)

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

  # -- New event handlers (comprehensive MIDI settings) --

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :selected_tab, tab)}
  end

  def handle_event("toggle_monitor_listen", _params, socket) do
    if socket.assigns.monitor_listening do
      {:noreply, assign(socket, :monitor_listening, false)}
    else
      # Subscribe to all input devices for monitoring
      for device <- socket.assigns.devices,
          device.direction in [:input, :duplex] do
        Dispatcher.subscribe(device.port_id)
      end

      {:noreply, assign(socket, :monitor_listening, true)}
    end
  end

  def handle_event("clear_monitor", _params, socket) do
    {:noreply, assign(socket, :midi_monitor, [])}
  end

  def handle_event("start_learn_action", %{"action" => action}, socket) do
    action_atom = String.to_existing_atom(action)
    device_name = socket.assigns.selected_device

    socket = assign(socket, :selected_action, action_atom)

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
    # Monitor: accumulate messages when monitoring is enabled
    socket =
      if socket.assigns.monitor_listening do
        entry = build_monitor_entry(port_id, message)
        monitor = [entry | socket.assigns.midi_monitor] |> Enum.take(50)
        assign(socket, :midi_monitor, monitor)
      else
        socket
      end

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
    <div id="midi-page" class="flex flex-col min-h-screen bg-gray-950 text-white">
      <SoundForgeWeb.Live.Components.AppHeader.app_header
        current_scope={@current_scope}
        current_user_id={@current_user_id}
        nav_tab={@nav_tab}
        nav_context={@nav_context}
        midi_devices={@midi_devices}
        midi_bpm={@midi_bpm}
        midi_transport={@midi_transport}
        pipelines={@pipelines}
        refreshing_midi={@refreshing_midi}
      />
    <div class="max-w-5xl mx-auto w-full p-6 space-y-6">
      <%!-- Page Header --%>
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-white">MIDI Settings</h1>
        <div class="flex items-center gap-3">
          <span class="text-sm text-gray-400">
            {device_count(@devices, @network_devices)} device{if device_count(@devices, @network_devices) != 1,
              do: "s"}
          </span>
          <div class={[
            "w-2.5 h-2.5 rounded-full",
            if(@devices != [] or @network_devices != [],
              do: "bg-green-400",
              else: "bg-gray-600"
            )
          ]} />
        </div>
      </div>
      <%!-- Tab bar --%>
      <div class="flex gap-1 bg-gray-900 rounded-xl p-1">
        <%= for {tab_id, tab_label} <- [
              {"overview", "Overview"},
              {"mappings", "Mappings"},
              {"monitor", "Monitor"},
              {"devices", "Devices"}
            ] do %>
          <button
            phx-click="select_tab"
            phx-value-tab={tab_id}
            class={"flex-1 py-2 px-4 text-sm font-medium rounded-lg transition-colors " <>
              if(@selected_tab == tab_id,
                do: "bg-gray-700 text-white",
                else: "text-gray-400 hover:text-gray-200 hover:bg-gray-800"
              )}
          >
            {tab_label}
          </button>
        <% end %>
      </div>
      <%!-- Overview Tab --%>
      <div :if={@selected_tab == "overview"} class="space-y-6">
        <%!-- Device status bar --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          <div
            :if={@devices == [] and @network_devices == []}
            class="col-span-full text-gray-500 italic text-sm"
          >
            No MIDI devices connected. Go to Devices tab to scan.
          </div>
          <div
            :for={device <- @devices}
            class="flex items-center gap-3 bg-gray-900 rounded-xl p-3 border border-gray-800"
          >
            <div class={[
              "w-2.5 h-2.5 rounded-full flex-shrink-0",
              if(Map.has_key?(@activity, device.port_id),
                do: "bg-green-400 animate-pulse",
                else: "bg-gray-600"
              )
            ]} />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-white truncate">{device.name}</p>
              <p class="text-xs text-gray-500">
                {type_label(device.type)} · {direction_label(device.direction)}
              </p>
            </div>
            <span class={status_badge_class(device.status)}>{status_label(device.status)}</span>
          </div>
        </div>
        <%!-- Device selector (for learn) --%>
        <div :if={@devices != []} class="flex items-center gap-3 flex-wrap">
          <label class="text-sm text-gray-400 flex-shrink-0">Learn Device:</label>
          <form phx-change="select_device" class="flex-1 max-w-xs">
            <select
              class="select select-bordered select-sm w-full"
              name="device"
            >
              <option value="">Select device...</option>
              <option :for={d <- @devices} value={d.name} selected={@selected_device == d.name}>
                {d.name}
              </option>
            </select>
          </form>
          <div :if={@learn_mode} class="flex items-center gap-2 text-sm">
            <span class="w-2 h-2 rounded-full bg-yellow-400 animate-pulse inline-block" />
            <span class="text-yellow-400">Listening for: {format_action(@selected_action)}</span>
            <button class="btn btn-xs btn-warning" phx-click="cancel_learn">Cancel</button>
          </div>
          <div :if={@learned_type && !@learn_mode} class="flex items-center gap-2 text-sm">
            <span class="badge badge-ghost badge-sm">{format_midi_type(@learned_type)}</span>
            <span class="text-gray-300">CH {@learned_channel} #{@learned_number}</span>
            <button :if={@selected_action} class="btn btn-xs btn-primary" phx-click="save_mapping">
              Save
            </button>
          </div>
        </div>
        <%!-- Controller Mapping Grid --%>
        <div class="space-y-4">
          <h3 class="text-sm font-semibold text-gray-200 uppercase tracking-wider">
            Controller Mapping
          </h3>
          <%= for {cat, cat_label, cat_actions} <- actions_by_category() do %>
            <div class="space-y-0.5">
              <div class="flex items-center gap-2 px-1 mb-1">
                <span class={category_badge_class(cat)}>{cat_label}</span>
              </div>
              <div class="bg-gray-900 rounded-xl border border-gray-800 overflow-hidden divide-y divide-gray-800/40">
                <%= for action <- cat_actions do %>
                  <% mapping = mapping_for_action(@mappings, action) %>
                  <div class="flex items-center gap-3 px-4 py-2.5 hover:bg-gray-800/30 transition-colors">
                    <div class="w-36 flex-shrink-0">
                      <span class="text-sm text-white">{format_action(action)}</span>
                    </div>
                    <div class="flex-1 flex items-center gap-2 min-w-0 text-xs">
                      <span :if={mapping} class="text-gray-300 truncate">{mapping.device_name}</span>
                      <span :if={mapping} class="badge badge-ghost badge-sm flex-shrink-0">
                        {format_midi_type(mapping.midi_type)}
                      </span>
                      <span :if={mapping} class="text-gray-400 flex-shrink-0">
                        CH {mapping.channel} #{mapping.number}
                      </span>
                      <span :if={!mapping} class="text-gray-600 italic">unmapped</span>
                    </div>
                    <div class="flex items-center gap-1.5 flex-shrink-0">
                      <button
                        class={"btn btn-xs " <>
                          if(@learn_mode && @selected_action == action,
                            do: "btn-warning animate-pulse",
                            else: "btn-outline btn-accent"
                          )}
                        phx-click="start_learn_action"
                        phx-value-action={action}
                        disabled={is_nil(@selected_device) ||
                          (@learn_mode && @selected_action != action)}
                      >
                        {cond do
                          @learn_mode && @selected_action == action -> "Listening..."
                          mapping -> "Remap"
                          true -> "Learn"
                        end}
                      </button>
                      <button
                        :if={mapping}
                        class="btn btn-ghost btn-xs text-error"
                        phx-click="delete_mapping"
                        phx-value-id={mapping.id}
                      >
                        ×
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
        <%!-- CC / Note Heatmap --%>
        <div class="space-y-4">
          <h3 class="text-sm font-semibold text-gray-200 uppercase tracking-wider">
            CC / Note Map (0–127)
          </h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <%!-- CC Map --%>
            <div class="space-y-2">
              <p class="text-xs text-gray-500 font-mono">CC Numbers</p>
              <div class="grid gap-0.5" style="grid-template-columns: repeat(16, minmax(0, 1fr));">
                <%= for n <- 0..127 do %>
                  <% cat = number_category(@mappings, :cc, n) %>
                  <div
                    class={"w-full aspect-square rounded-[2px] cursor-default transition-colors " <>
                      category_cell_class(cat)}
                    title={"CC #{n}#{if cat, do: " (#{category_label(cat)})", else: ""}"}
                  />
                <% end %>
              </div>
            </div>
            <%!-- Note Map --%>
            <div class="space-y-2">
              <p class="text-xs text-gray-500 font-mono">Note Numbers</p>
              <div class="grid gap-0.5" style="grid-template-columns: repeat(16, minmax(0, 1fr));">
                <%= for n <- 0..127 do %>
                  <% cat = number_category(@mappings, :note_on, n) %>
                  <div
                    class={"w-full aspect-square rounded-[2px] cursor-default transition-colors " <>
                      category_cell_class(cat)}
                    title={"Note #{n}#{if cat, do: " (#{category_label(cat)})", else: ""}"}
                  />
                <% end %>
              </div>
            </div>
          </div>
          <%!-- Legend --%>
          <div class="flex items-center gap-4 flex-wrap">
            <%= for {cat, label} <- [
                  {:transport, "Transport"},
                  {:dj, "DJ"},
                  {:pads, "Pads"},
                  {:stems, "Stems"},
                  {nil, "Unused"}
                ] do %>
              <div class="flex items-center gap-1.5">
                <div class={"w-3 h-3 rounded-[2px] " <> category_cell_class(cat)} />
                <span class="text-xs text-gray-400">{label}</span>
              </div>
            <% end %>
          </div>
        </div>
      </div>
      <%!-- Mappings Tab --%>
      <div :if={@selected_tab == "mappings"} class="space-y-6">
        <div :if={@mapping_flash} class="alert alert-info text-sm">{@mapping_flash}</div>
        <%!-- Preset Loader --%>
        <div class="flex items-center gap-3 flex-wrap">
          <span class="text-sm text-gray-400">Load Preset:</span>
          <button
            class={["btn btn-sm btn-outline", @selected_preset == "generic" && "btn-active"]}
            phx-click="load_preset"
            phx-value-preset="generic"
          >
            Generic
          </button>
          <button
            class={["btn btn-sm btn-outline", @selected_preset == "mpc" && "btn-active"]}
            phx-click="load_preset"
            phx-value-preset="mpc"
          >
            MPC
          </button>
        </div>
        <%!-- New Mapping Form --%>
        <div class="card bg-base-200 shadow-md">
          <div class="card-body p-4 space-y-4">
            <h3 class="font-medium text-white">New Mapping</h3>
            <div class="flex flex-wrap items-end gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text text-gray-400">Device</span></label>
                <form phx-change="select_device">
                  <select
                    class="select select-bordered select-sm"
                    name="device"
                  >
                    <option value="">Select device...</option>
                    <option :for={d <- @devices} value={d.name} selected={@selected_device == d.name}>
                      {d.name}
                    </option>
                  </select>
                </form>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-gray-400">Action</span></label>
                <form phx-change="select_action">
                  <select
                    class="select select-bordered select-sm"
                    name="action"
                  >
                    <option value="">Select action...</option>
                    <%= for {_cat, cat_label, cat_actions} <- actions_by_category() do %>
                      <optgroup label={cat_label}>
                        <%= for action <- cat_actions do %>
                          <option value={action} selected={@selected_action == action}>
                            {format_action(action)}
                          </option>
                        <% end %>
                      </optgroup>
                    <% end %>
                  </select>
                </form>
              </div>
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
              <div :if={@learned_type} class="flex items-center gap-2 text-sm text-gray-300">
                <span class="badge badge-ghost badge-sm">{format_midi_type(@learned_type)}</span>
                <span>CH {@learned_channel}</span>
                <span>#{@learned_number}</span>
              </div>
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
        <%!-- Mappings Table --%>
        <div :if={@mappings != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th class="text-gray-400">Category</th>
                <th class="text-gray-400">Action</th>
                <th class="text-gray-400">Device</th>
                <th class="text-gray-400">Type</th>
                <th class="text-gray-400">CH</th>
                <th class="text-gray-400">#</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={mapping <- @mappings} class="hover">
                <td>
                  <span class={category_badge_class(action_category(mapping.action))}>
                    {category_label(action_category(mapping.action))}
                  </span>
                </td>
                <td class="text-white">{format_action(mapping.action)}</td>
                <td class="text-gray-300 text-xs max-w-[140px] truncate">{mapping.device_name}</td>
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
      <%!-- Monitor Tab --%>
      <div :if={@selected_tab == "monitor"} class="space-y-4">
        <div class="flex items-center justify-between">
          <h3 class="text-base font-semibold text-gray-200">MIDI Activity Monitor</h3>
          <div class="flex items-center gap-2">
            <button
              class={"btn btn-sm " <> if(@monitor_listening, do: "btn-error", else: "btn-success")}
              phx-click="toggle_monitor_listen"
            >
              {if @monitor_listening, do: "Stop", else: "Start Monitoring"}
            </button>
            <button
              :if={@midi_monitor != []}
              class="btn btn-sm btn-ghost"
              phx-click="clear_monitor"
            >
              Clear
            </button>
          </div>
        </div>
        <div
          :if={!@monitor_listening && @midi_monitor == []}
          class="text-center py-12 text-gray-500 text-sm"
        >
          <p class="mb-2">No MIDI activity recorded.</p>
          <p>Click "Start Monitoring" to capture messages from connected input devices.</p>
        </div>
        <div
          :if={@monitor_listening && @midi_monitor == []}
          class="flex items-center gap-2 py-4 text-sm text-green-400"
        >
          <span class="w-2 h-2 rounded-full bg-green-400 animate-pulse inline-block flex-shrink-0" />
          Listening for MIDI input... send messages from your controller.
        </div>
        <div
          :if={@midi_monitor != []}
          class="bg-gray-950 rounded-xl border border-gray-800 overflow-hidden"
        >
          <div class="flex items-center justify-between px-4 py-2 border-b border-gray-800 bg-gray-900/50">
            <span class="text-xs text-gray-400 font-mono">TYPE</span>
            <span class="text-xs text-gray-400 font-mono">CH</span>
            <span class="text-xs text-gray-400 font-mono">#</span>
            <span class="text-xs text-gray-400 font-mono flex-1 ml-4">VALUE</span>
            <span class="text-xs text-gray-400 font-mono">PORT</span>
          </div>
          <div class="overflow-y-auto max-h-96 divide-y divide-gray-800/30">
            <div
              :for={entry <- @midi_monitor}
              class="flex items-center gap-3 px-4 py-1.5 font-mono text-xs hover:bg-gray-900/50 transition-colors"
            >
              <span class={"badge badge-sm flex-shrink-0 " <> monitor_type_class(entry.type)}>
                {format_midi_type(entry.type)}
              </span>
              <span class="text-gray-400 w-8 text-center flex-shrink-0">{entry.channel}</span>
              <span class="text-gray-300 w-8 text-center flex-shrink-0">{entry.number}</span>
              <div class="flex-1 flex items-center gap-2 min-w-0">
                <div class="flex-1 bg-gray-800 rounded-full h-1 overflow-hidden">
                  <div
                    class="h-full bg-cyan-500 rounded-full"
                    style={"width: #{round((entry.value || 0) / 127 * 100)}%"}
                  />
                </div>
                <span class="text-gray-500 w-8 text-right flex-shrink-0">{entry.value || 0}</span>
              </div>
              <span class="text-gray-700 text-[10px] truncate max-w-[80px] flex-shrink-0">
                {entry.port_id}
              </span>
            </div>
          </div>
        </div>
      </div>
      <%!-- Devices Tab --%>
      <div :if={@selected_tab == "devices"} class="space-y-6">
        <%!-- Connected Devices --%>
        <div class="space-y-3">
          <h3 class="text-base font-semibold text-gray-200">Connected Devices</h3>
          <div :if={@devices == []} class="text-gray-500 italic text-sm">
            No MIDI devices connected.
          </div>
          <div :for={device <- @devices} class="card bg-base-200 shadow-md">
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
                <span class={direction_badge_class(device.direction)}>
                  {direction_label(device.direction)}
                </span>
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
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <h3 class="text-base font-semibold text-gray-200">Network MIDI Sessions</h3>
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
          <div :for={net_dev <- @network_devices} class="card bg-base-200 shadow-md">
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
      </div>
    </div>
    </div>
    """
  end

  # -- Private Helpers --

  defp resolve_user_id(%{id: id}, _session) when is_integer(id), do: id

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

  # -- Comprehensive MIDI Settings Helpers --

  defp actions_by_category do
    [
      {:transport, "Transport", [:play, :stop, :next_track, :prev_track, :seek, :bpm_tap]},
      {:dj, "DJ", [:dj_play, :dj_cue, :dj_crossfader, :dj_loop_toggle, :dj_loop_size, :dj_pitch]},
      {:pads, "Pads",
       [:pad_trigger, :pad_volume, :pad_pitch, :pad_velocity, :pad_master_volume]},
      {:stems, "Stems", [:stem_solo, :stem_mute, :stem_volume]}
    ]
  end

  defp action_category(action)
       when action in [:play, :stop, :next_track, :prev_track, :seek, :bpm_tap],
       do: :transport

  defp action_category(action)
       when action in [:dj_play, :dj_cue, :dj_crossfader, :dj_loop_toggle, :dj_loop_size,
                       :dj_pitch],
       do: :dj

  defp action_category(action)
       when action in [:pad_trigger, :pad_volume, :pad_pitch, :pad_velocity, :pad_master_volume],
       do: :pads

  defp action_category(action) when action in [:stem_solo, :stem_mute, :stem_volume], do: :stems
  defp action_category(_), do: :other

  defp category_label(:transport), do: "Transport"
  defp category_label(:dj), do: "DJ"
  defp category_label(:pads), do: "Pads"
  defp category_label(:stems), do: "Stems"
  defp category_label(_), do: "Other"

  defp category_badge_class(:transport), do: "badge badge-sm bg-blue-700 border-0 text-white"
  defp category_badge_class(:dj), do: "badge badge-sm bg-cyan-700 border-0 text-white"
  defp category_badge_class(:pads), do: "badge badge-sm bg-purple-700 border-0 text-white"
  defp category_badge_class(:stems), do: "badge badge-sm bg-green-700 border-0 text-white"
  defp category_badge_class(_), do: "badge badge-sm badge-ghost"

  defp category_cell_class(nil), do: "bg-gray-800 hover:bg-gray-700"
  defp category_cell_class(:transport), do: "bg-blue-700/80 hover:bg-blue-600"
  defp category_cell_class(:dj), do: "bg-cyan-700/80 hover:bg-cyan-600"
  defp category_cell_class(:pads), do: "bg-purple-700/80 hover:bg-purple-600"
  defp category_cell_class(:stems), do: "bg-green-700/80 hover:bg-green-600"
  defp category_cell_class(_), do: "bg-gray-700"

  defp mapping_for_action(mappings, action) do
    Enum.find(mappings, &(&1.action == action))
  end

  defp number_category(mappings, midi_type, number) do
    case Enum.find(mappings, &(&1.midi_type == midi_type && &1.number == number)) do
      nil -> nil
      mapping -> action_category(mapping.action)
    end
  end

  defp build_monitor_entry(port_id, message) do
    type = Map.get(message, :type, :unknown)
    channel = Map.get(message, :channel, 0)
    data = Map.get(message, :data, %{})

    number =
      Map.get(data, :number, Map.get(data, :controller, Map.get(data, :note, 0))) || 0

    value = Map.get(data, :value, Map.get(data, :velocity, 0)) || 0

    %{
      port_id: port_id,
      type: type,
      channel: channel,
      number: number,
      value: value,
      time: System.monotonic_time(:millisecond)
    }
  end

  defp monitor_type_class(:cc), do: "badge-warning"
  defp monitor_type_class(:note_on), do: "badge-success"
  defp monitor_type_class(:note_off), do: "badge-error"
  defp monitor_type_class(_), do: "badge-ghost"
end
