defmodule SoundForgeWeb.MidiLive do
  @moduledoc """
  MIDI Settings — Logic Pro-style 3-column layout.

  Column 1 (Controllers): connected devices + OSC server status
  Column 2 (Modules): SFA action categories with per-action learn/remap
  Column 3 (Visual Mapper): SVG schematic of selected controller,
    click-to-map interaction, auto-preset loader, per-controller mappings

  Bottom strip: collapsible live MIDI monitor.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.MIDI.{
    ControllerRegistry,
    DeviceManager,
    Dispatcher,
    Mapping,
    Mappings,
    NetworkDiscovery
  }

  alias SoundForge.MIDI.Profiles.{MPC, MVAVE}

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      DeviceManager.subscribe()
    end

    current_user_id = resolve_user_id(socket.assigns[:current_user], session)
    devices = DeviceManager.list_devices()
    network_devices = NetworkDiscovery.list_network_devices()
    mappings = if current_user_id, do: Mappings.list_mappings(current_user_id), else: []

    # Auto-select the first input device, if any
    default_controller =
      Enum.find(devices, fn d -> d.direction in [:input, :duplex] end)

    socket =
      socket
      |> assign(:page_title, "MIDI / OSC")
      |> assign(:current_scope, socket.assigns[:current_scope])
      |> assign(:current_user_id, current_user_id)
      |> assign(:nav_tab, :library)
      |> assign(:nav_context, :all_tracks)
      # AppHeader assigns
      |> assign(:midi_devices, devices)
      |> assign(:midi_bpm, nil)
      |> assign(:midi_transport, :stopped)
      |> assign(:pipelines, %{})
      |> assign(:refreshing_midi, false)
      # Device state
      |> assign(:devices, devices)
      |> assign(:network_devices, network_devices)
      |> assign(:listening, MapSet.new())
      |> assign(:activity, %{})
      |> assign(:scanning, false)
      # Controller selection (3-column)
      |> assign(:selected_controller_port_id, default_controller && default_controller.port_id)
      |> assign(:visual_tab, nil)
      # Mapping/learn state
      |> assign(:mappings, mappings)
      |> assign(:learn_mode, false)
      |> assign(:learn_device, nil)
      |> assign(:selected_action, nil)
      |> assign(:selected_device, default_controller && default_controller.name)
      |> assign(:selected_element, nil)
      |> assign(:learned_type, nil)
      |> assign(:learned_channel, nil)
      |> assign(:learned_number, nil)
      |> assign(:selected_preset, nil)
      |> assign(:mapping_flash, nil)
      # Monitor strip
      |> assign(:midi_monitor, [])
      |> assign(:monitor_listening, false)
      |> assign(:monitor_expanded, false)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Navigation
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("nav_tab", %{"tab" => tab}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/?tab=#{tab}")}
  end

  # ---------------------------------------------------------------------------
  # Controller column events
  # ---------------------------------------------------------------------------

  def handle_event("select_controller", %{"port_id" => port_id}, socket) do
    device = Enum.find(socket.assigns.devices, &(&1.port_id == port_id))
    device_name = device && device.name

    {:noreply,
     socket
     |> assign(:selected_controller_port_id, port_id)
     |> assign(:selected_device, device_name)
     |> assign(:selected_element, nil)
     |> assign(:learn_mode, false)
     |> assign(:learn_device, nil)}
  end

  def handle_event("refresh_devices", _params, socket) do
    devices = DeviceManager.list_devices()
    network_devices = NetworkDiscovery.list_network_devices()

    {:noreply,
     socket
     |> assign(:devices, devices)
     |> assign(:network_devices, network_devices)
     |> assign(:refreshing_midi, true)
     |> then(fn s ->
       Process.send_after(self(), :clear_refresh_flash, 1500)
       s
     end)}
  end

  def handle_event("scan_network", _params, socket) do
    NetworkDiscovery.scan_now()
    {:noreply, assign(socket, :scanning, true)}
  end

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

  # ---------------------------------------------------------------------------
  # Visual mapper — SVG click-to-map
  # ---------------------------------------------------------------------------

  def handle_event("select_element", %{"kind" => kind, "index" => idx_str}, socket) do
    index = String.to_integer(idx_str)
    element = %{kind: String.to_atom(kind), index: index}

    # Start learn mode for the selected element's controller
    device_name = socket.assigns.selected_device

    socket =
      if device_name do
        device = Enum.find(socket.assigns.devices, &(&1.name == device_name))

        if device do
          Dispatcher.subscribe(device.port_id)

          socket
          |> assign(:selected_element, element)
          |> assign(:learn_mode, true)
          |> assign(:learn_device, device.port_id)
          |> assign(:learned_type, nil)
          |> assign(:learned_channel, nil)
          |> assign(:learned_number, nil)
          |> assign(:mapping_flash, "Waiting for MIDI input from #{device_name}...")
        else
          assign(socket, :selected_element, element)
        end
      else
        assign(socket, :selected_element, element)
      end

    {:noreply, socket}
  end

  def handle_event("clear_element_selection", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_element, nil)
     |> assign(:learn_mode, false)
     |> assign(:learn_device, nil)
     |> assign(:learned_type, nil)
     |> assign(:learned_channel, nil)
     |> assign(:learned_number, nil)}
  end

  # ---------------------------------------------------------------------------
  # Preset auto-map
  # ---------------------------------------------------------------------------

  def handle_event("load_preset", %{"preset" => preset}, socket) do
    user_id = socket.assigns.current_user_id

    unless user_id do
      {:noreply, assign(socket, :mapping_flash, "No user session.")}
    else
      result = load_preset_mappings(preset, user_id, socket)

      case result do
        {:error, msg} ->
          {:noreply, assign(socket, :mapping_flash, msg)}

        _ ->
          mappings = Mappings.list_mappings(user_id)

          {:noreply,
           socket
           |> assign(:mappings, mappings)
           |> assign(:selected_preset, preset)
           |> assign(:mapping_flash, "Preset '#{preset}' loaded.")}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Modules column — learn/remap/delete
  # ---------------------------------------------------------------------------

  def handle_event("select_action", %{"action" => action}, socket) do
    action_atom = if action == "", do: nil, else: String.to_existing_atom(action)
    {:noreply, assign(socket, :selected_action, action_atom)}
  end

  def handle_event("select_device", %{"device" => device_name}, socket) do
    device_name = if device_name == "", do: nil, else: device_name
    {:noreply, assign(socket, :selected_device, device_name)}
  end

  def handle_event("start_learn_action", %{"action" => action}, socket) do
    action_atom = String.to_existing_atom(action)
    device_name = socket.assigns.selected_device
    socket = assign(socket, :selected_action, action_atom)

    if device_name do
      device = Enum.find(socket.assigns.devices, &(&1.name == device_name))

      if device do
        Dispatcher.subscribe(device.port_id)

        {:noreply,
         socket
         |> assign(:learn_mode, true)
         |> assign(:learn_device, device.port_id)
         |> assign(:learned_type, nil)
         |> assign(:learned_channel, nil)
         |> assign(:learned_number, nil)
         |> assign(:selected_element, nil)}
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

    {:noreply,
     socket
     |> assign(:learn_mode, false)
     |> assign(:learn_device, nil)
     |> assign(:selected_element, nil)
     |> assign(:mapping_flash, nil)}
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
        {:ok, _} ->
          mappings = Mappings.list_mappings(user_id)

          {:noreply,
           socket
           |> assign(:mappings, mappings)
           |> assign(:learned_type, nil)
           |> assign(:learned_channel, nil)
           |> assign(:learned_number, nil)
           |> assign(:selected_action, nil)
           |> assign(:selected_element, nil)
           |> assign(:mapping_flash, "Mapping saved.")}

        {:error, _} ->
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

  # ---------------------------------------------------------------------------
  # MIDI Monitor strip
  # ---------------------------------------------------------------------------

  def handle_event("toggle_monitor", _params, socket) do
    {:noreply, update(socket, :monitor_expanded, &(!&1))}
  end

  def handle_event("toggle_monitor_listen", _params, socket) do
    if socket.assigns.monitor_listening do
      {:noreply, assign(socket, :monitor_listening, false)}
    else
      for device <- socket.assigns.devices, device.direction in [:input, :duplex] do
        Dispatcher.subscribe(device.port_id)
      end

      {:noreply, assign(socket, :monitor_listening, true)}
    end
  end

  def handle_event("clear_monitor", _params, socket) do
    {:noreply, assign(socket, :midi_monitor, [])}
  end

  # Catch-all: ignore unhandled events (e.g. pwa_midi_available from root layout hook)
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # PubSub info handlers
  # ---------------------------------------------------------------------------

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

    {:noreply, socket |> assign(:network_devices, network_devices) |> assign(:scanning, false)}
  end

  def handle_info({:network_device_disappeared, device}, socket) do
    network_devices = Enum.reject(socket.assigns.network_devices, &(&1.id == device.id))
    {:noreply, assign(socket, :network_devices, network_devices)}
  end

  def handle_info(:clear_refresh_flash, socket) do
    {:noreply, assign(socket, :refreshing_midi, false)}
  end

  def handle_info({:midi_message, port_id, message}, socket) do
    socket =
      if socket.assigns.monitor_listening do
        entry = build_monitor_entry(port_id, message)
        monitor = [entry | socket.assigns.midi_monitor] |> Enum.take(100)
        assign(socket, :midi_monitor, monitor)
      else
        socket
      end

    if socket.assigns.learn_mode && socket.assigns.learn_device == port_id do
      {midi_type, channel, number} = extract_mapping_from_message(message)

      if midi_type do
        Phoenix.PubSub.unsubscribe(SoundForge.PubSub, Dispatcher.topic(port_id))

        {:noreply,
         socket
         |> assign(:learn_mode, false)
         |> assign(:learn_device, nil)
         |> assign(:learned_type, midi_type)
         |> assign(:learned_channel, channel)
         |> assign(:learned_number, number)
         |> assign(:mapping_flash, "Captured: #{format_midi_type(midi_type)} CH#{channel} ##{number} — click Save to confirm.")}
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
        ts when is_integer(ts) and now - ts >= 280 -> Map.delete(socket.assigns.activity, port_id)
        _ -> socket.assigns.activity
      end

    {:noreply, assign(socket, :activity, activity)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    # Pre-compute controller-specific data for this render
    assigns =
      assign(assigns, :selected_controller,
        Enum.find(assigns.devices, &(&1.port_id == assigns.selected_controller_port_id))
      )

    assigns =
      assign(assigns, :controller_mappings,
        if assigns.selected_controller do
          Enum.filter(assigns.mappings, &(&1.device_name == assigns.selected_controller.name))
        else
          []
        end
      )

    assigns =
      assign(assigns, :registry_entry,
        if assigns.selected_controller do
          ControllerRegistry.detect(assigns.selected_controller.name)
        else
          nil
        end
      )

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

      <%!-- Main 3-column layout --%>
      <div class="flex flex-1 gap-0 min-h-0 overflow-hidden" style="height: calc(100vh - 56px);">
        <%!-- ============================================================ --%>
        <%!-- Column 1: Controllers --%>
        <%!-- ============================================================ --%>
        <div class="w-64 flex-shrink-0 border-r border-gray-800 bg-gray-950 flex flex-col overflow-y-auto">
          <div class="px-3 pt-4 pb-2 flex items-center justify-between">
            <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Controllers</span>
            <button
              phx-click="refresh_devices"
              class="text-gray-600 hover:text-gray-300 transition-colors"
              title="Refresh"
            >
              <svg class={["w-3.5 h-3.5", @refreshing_midi && "animate-spin"]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
            </button>
          </div>

          <%!-- USB / Virtual Devices --%>
          <div class="px-2 space-y-0.5 pb-2">
            <div :if={@devices == []} class="px-2 py-3 text-xs text-gray-600 italic">
              No MIDI devices found.
            </div>

            <button
              :for={device <- @devices}
              phx-click="select_controller"
              phx-value-port_id={device.port_id}
              class={[
                "w-full text-left px-2 py-2.5 rounded-lg transition-colors group",
                if(@selected_controller_port_id == device.port_id,
                  do: "bg-purple-900/50 border border-purple-700/50",
                  else: "hover:bg-gray-800/60 border border-transparent"
                )
              ]}
            >
              <div class="flex items-center gap-2">
                <div class={[
                  "w-2 h-2 rounded-full flex-shrink-0",
                  if(Map.has_key?(@activity, device.port_id),
                    do: "bg-green-400 animate-pulse",
                    else: "bg-gray-600"
                  )
                ]} />
                <span class="text-sm text-white font-medium truncate flex-1">{device.name}</span>
                <span class={direction_badge_class(device.direction)}>
                  {direction_label(device.direction)}
                </span>
              </div>
              <div class="ml-4 mt-0.5 flex items-center gap-2">
                <span class="text-[10px] text-gray-500">{type_label(device.type)}</span>
                <span class={["text-[10px] font-medium", if(device.status == :connected, do: "text-green-500", else: "text-red-400")]}>
                  {status_label(device.status)}
                </span>
              </div>
              <%!-- Registry match indicator --%>
              <% reg = ControllerRegistry.detect(device.name) %>
              <div :if={reg} class="ml-4 mt-0.5">
                <span class="text-[10px] text-purple-400">{reg.name}</span>
              </div>
            </button>
          </div>

          <%!-- Network MIDI --%>
          <div :if={@network_devices != []} class="px-3 pt-3 pb-1">
            <span class="text-[10px] font-semibold text-gray-600 uppercase tracking-wider">Network</span>
          </div>
          <div class="px-2 space-y-0.5 pb-2">
            <div
              :for={net <- @network_devices}
              class="px-2 py-2 rounded-lg bg-gray-900/50 border border-gray-800"
            >
              <div class="flex items-center gap-2">
                <div class="w-2 h-2 rounded-full bg-blue-400 flex-shrink-0" />
                <span class="text-sm text-white truncate flex-1">{net.name}</span>
                <span class="text-[10px] text-blue-400">RTP</span>
              </div>
              <div class="ml-4 mt-0.5 text-[10px] text-gray-600">
                {Map.get(net, :host, "?")}:{Map.get(net, :port, "?")}
              </div>
            </div>
            <button
              class={["w-full mt-1 px-2 py-1.5 text-xs text-gray-500 hover:text-gray-300 rounded transition-colors flex items-center gap-1.5", @scanning && "opacity-50"]}
              phx-click="scan_network"
              disabled={@scanning}
            >
              <svg class={["w-3 h-3", @scanning && "animate-spin"]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
              {if @scanning, do: "Scanning...", else: "Scan Network"}
            </button>
          </div>

          <%!-- OSC Server --%>
          <div class="mt-auto border-t border-gray-800 px-3 py-3">
            <div class="flex items-center gap-2 mb-1">
              <div class="w-2 h-2 rounded-full bg-cyan-500 flex-shrink-0" />
              <span class="text-xs font-medium text-gray-300">OSC Server</span>
              <span class="ml-auto text-[10px] text-cyan-400 font-mono">UDP :8000</span>
            </div>
            <p class="text-[10px] text-gray-600 mb-2">Open Sound Control — receive from any OSC app</p>
            <a
              href={~p"/export/osc-layout"}
              class="block text-center px-2 py-1 text-[10px] rounded border border-gray-700 text-gray-400 hover:border-cyan-700 hover:text-cyan-400 transition-colors"
              download="sfa-touchosc.tosc"
            >
              Download TouchOSC Layout
            </a>
          </div>
        </div>

        <%!-- ============================================================ --%>
        <%!-- Column 2: Modules (Actions) --%>
        <%!-- ============================================================ --%>
        <div class="flex-1 overflow-y-auto bg-gray-950">
          <div class="px-4 pt-4 pb-2 flex items-center justify-between border-b border-gray-800/60 sticky top-0 bg-gray-950 z-10">
            <div class="flex items-center gap-3">
              <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Modules</span>
              <div :if={@selected_device} class="text-xs text-gray-600">
                → <span class="text-gray-400">{@selected_device}</span>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <%!-- Flash message --%>
              <div :if={@mapping_flash} class="text-xs text-purple-400 animate-pulse">{@mapping_flash}</div>
              <%!-- Save captured mapping --%>
              <button
                :if={@learned_type && @selected_action && @selected_device}
                phx-click="save_mapping"
                class="px-3 py-1 text-xs bg-purple-700 hover:bg-purple-600 text-white rounded transition-colors"
              >
                Save Mapping
              </button>
              <%!-- Cancel learn --%>
              <button
                :if={@learn_mode}
                phx-click="cancel_learn"
                class="px-3 py-1 text-xs bg-yellow-700/50 hover:bg-yellow-700 text-yellow-300 rounded transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>

          <%!-- No controller selected --%>
          <div :if={@devices == []} class="px-4 py-8 text-center text-gray-600 text-sm">
            No MIDI devices connected. Connect a controller and click Refresh.
          </div>

          <%!-- Device selector for learn --%>
          <div :if={@devices != []} class="px-4 py-2 border-b border-gray-800/40 flex items-center gap-3">
            <span class="text-xs text-gray-500 flex-shrink-0">Learn device:</span>
            <form phx-change="select_device" class="flex-1">
              <select class="w-full bg-gray-900 border border-gray-700 rounded text-sm text-white px-2 py-1 focus:border-purple-600 focus:outline-none" name="device">
                <option value="">Select device...</option>
                <option :for={d <- @devices} value={d.name} selected={@selected_device == d.name}>{d.name}</option>
              </select>
            </form>
            <div :if={@learn_mode} class="flex items-center gap-1.5 text-xs text-yellow-400">
              <span class="w-1.5 h-1.5 rounded-full bg-yellow-400 animate-pulse inline-block" />
              Listening...
            </div>
            <div :if={@learned_type && !@learn_mode} class="flex items-center gap-1.5 text-xs">
              <span class="bg-gray-800 px-1.5 py-0.5 rounded text-gray-300 font-mono">
                {format_midi_type(@learned_type)} CH{@learned_channel} #{@learned_number}
              </span>
            </div>
          </div>

          <%!-- Action categories --%>
          <div class="divide-y divide-gray-800/40">
            <%= for {cat, cat_label, cat_actions} <- actions_by_category() do %>
              <div class="py-1">
                <div class="px-4 py-1.5 flex items-center gap-2">
                  <span class={category_pill_class(cat)}>{cat_label}</span>
                  <span class="text-[10px] text-gray-600">
                    {count_mapped_actions(@mappings, cat_actions)}/{length(cat_actions)} mapped
                  </span>
                </div>

                <div class="divide-y divide-gray-800/20">
                  <%= for action <- cat_actions do %>
                    <% mapping = mapping_for_action(@mappings, action) %>
                    <div class={[
                      "flex items-center gap-3 px-4 py-2 hover:bg-gray-900/40 transition-colors",
                      @learn_mode && @selected_action == action && "bg-yellow-900/20"
                    ]}>
                      <%!-- Action name --%>
                      <span class="w-32 flex-shrink-0 text-sm text-white">{format_action(action)}</span>

                      <%!-- Current mapping --%>
                      <div class="flex-1 flex items-center gap-2 min-w-0">
                        <div :if={mapping} class="flex items-center gap-1.5 text-xs">
                          <span class="text-gray-400 truncate max-w-[110px]">{shorten_device_name(mapping.device_name)}</span>
                          <span class="bg-gray-800 px-1.5 py-0.5 rounded text-gray-300 font-mono flex-shrink-0">
                            {format_midi_type(mapping.midi_type)} {mapping.number}
                          </span>
                        </div>
                        <span :if={!mapping} class="text-xs text-gray-700 italic">unmapped</span>
                      </div>

                      <%!-- Actions --%>
                      <div class="flex items-center gap-1 flex-shrink-0">
                        <button
                          class={[
                            "px-2 py-0.5 text-xs rounded transition-colors",
                            cond do
                              @learn_mode && @selected_action == action ->
                                "bg-yellow-600 text-white animate-pulse"
                              @selected_device ->
                                "bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white"
                              true ->
                                "bg-gray-900 text-gray-600 cursor-not-allowed"
                            end
                          ]}
                          phx-click="start_learn_action"
                          phx-value-action={action}
                          disabled={is_nil(@selected_device) || (@learn_mode && @selected_action != action)}
                        >
                          {cond do
                            @learn_mode && @selected_action == action -> "Listening..."
                            mapping -> "Remap"
                            true -> "Learn"
                          end}
                        </button>
                        <button
                          :if={mapping}
                          class="px-1.5 py-0.5 text-xs text-red-500 hover:text-red-400 hover:bg-red-900/20 rounded transition-colors"
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

          <%!-- OSC Addresses reference --%>
          <div class="px-4 pt-4 pb-6 border-t border-gray-800/40 mt-2">
            <div class="flex items-center gap-2 mb-3">
              <span class="text-[10px] font-semibold text-gray-500 uppercase tracking-wider">OSC Addresses</span>
              <span class="text-[10px] text-gray-700">udp/8000 — use with TouchOSC, GrandMA, etc.</span>
            </div>
            <div class="grid grid-cols-2 gap-x-4 gap-y-1">
              <%= for {addr, desc} <- osc_addresses() do %>
                <div class="flex items-center gap-2">
                  <code class="text-[10px] text-cyan-500 font-mono">{addr}</code>
                  <span class="text-[10px] text-gray-600">{desc}</span>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- ============================================================ --%>
        <%!-- Column 3: Visual Mapper --%>
        <%!-- ============================================================ --%>
        <div class="w-72 flex-shrink-0 border-l border-gray-800 bg-gray-950 flex flex-col overflow-y-auto">
          <div class="px-3 pt-4 pb-2 border-b border-gray-800/60">
            <span class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Visual Mapper</span>
          </div>

          <%!-- No controller selected --%>
          <div :if={is_nil(@selected_controller)} class="flex-1 flex items-center justify-center px-4">
            <p class="text-xs text-gray-600 text-center">Select a controller from the left column</p>
          </div>

          <%!-- Controller visual --%>
          <div :if={@selected_controller} class="flex-1 flex flex-col">
            <%!-- Controller name + status --%>
            <div class="px-3 py-2 border-b border-gray-800/40">
              <div class="flex items-center gap-2">
                <div class={[
                  "w-2 h-2 rounded-full",
                  if(Map.has_key?(@activity, @selected_controller.port_id),
                    do: "bg-green-400 animate-pulse",
                    else: "bg-gray-600"
                  )
                ]} />
                <span class="text-sm font-medium text-white">{@selected_controller.name}</span>
              </div>
              <div class="flex items-center gap-2 mt-0.5">
                <span class={type_badge_class(@selected_controller.type)}>{type_label(@selected_controller.type)}</span>
                <span class={direction_badge_class(@selected_controller.direction)}>{direction_label(@selected_controller.direction)}</span>
              </div>
            </div>

            <%!-- SVG Controller Visual --%>
            <div class="px-3 py-3">
              <%= if @registry_entry do %>
                <.controller_svg
                  registry={@registry_entry}
                  mappings={@controller_mappings}
                  selected_element={@selected_element}
                  activity={@activity}
                  selected_controller_port_id={@selected_controller_port_id}
                  learn_mode={@learn_mode}
                />
              <% else %>
                <%!-- Generic controller schematic --%>
                <div class="rounded-lg bg-gray-900 border border-gray-800 p-3 text-center">
                  <p class="text-xs text-gray-500 mb-2">Generic controller</p>
                  <div class="grid grid-cols-4 gap-1">
                    <%= for i <- 0..15 do %>
                      <% mapped = pad_mapped?(@controller_mappings, i) %>
                      <button
                        phx-click="select_element"
                        phx-value-kind="pad"
                        phx-value-index={i}
                        class={[
                          "aspect-square rounded text-[9px] font-mono transition-all",
                          cond do
                            @selected_element && @selected_element.kind == :pad && @selected_element.index == i ->
                              "bg-yellow-500 text-black"
                            mapped ->
                              "bg-purple-700 text-white"
                            true ->
                              "bg-gray-800 text-gray-600 hover:bg-gray-700"
                          end
                        ]}
                      >{i + 1}</button>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Learn state indicator --%>
            <div
              :if={@selected_element && @learn_mode}
              class="mx-3 mb-2 px-3 py-2 bg-yellow-900/30 border border-yellow-700/40 rounded-lg"
            >
              <div class="flex items-center gap-2 text-xs text-yellow-400">
                <span class="w-2 h-2 rounded-full bg-yellow-400 animate-pulse inline-block" />
                <span>Tap a control on your hardware...</span>
              </div>
            </div>

            <div
              :if={@learned_type && !@learn_mode && @selected_element}
              class="mx-3 mb-2 px-3 py-2 bg-purple-900/30 border border-purple-700/40 rounded-lg"
            >
              <p class="text-xs text-gray-400 mb-1.5">Captured:</p>
              <div class="flex items-center gap-2 mb-2">
                <span class="text-xs font-mono bg-gray-800 px-2 py-0.5 rounded text-purple-300">
                  {format_midi_type(@learned_type)} CH{@learned_channel} #{@learned_number}
                </span>
              </div>
              <p class="text-xs text-gray-500 mb-1.5">Map to:</p>
              <form phx-change="select_action" class="mb-2">
                <select class="w-full bg-gray-800 border border-gray-700 rounded text-xs text-white px-2 py-1" name="action">
                  <option value="">Choose action...</option>
                  <%= for {_cat, cat_label, cat_actions} <- actions_by_category() do %>
                    <optgroup label={cat_label}>
                      <option :for={action <- cat_actions} value={action} selected={@selected_action == action}>
                        {format_action(action)}
                      </option>
                    </optgroup>
                  <% end %>
                </select>
              </form>
              <button
                :if={@selected_action}
                phx-click="save_mapping"
                class="w-full py-1 text-xs bg-purple-700 hover:bg-purple-600 text-white rounded transition-colors"
              >
                Save Mapping
              </button>
            </div>

            <%!-- Auto-map presets --%>
            <div class="px-3 pb-3 border-t border-gray-800/40 pt-3">
              <p class="text-[10px] text-gray-500 uppercase tracking-wider mb-2">Auto Map Preset</p>
              <div class="flex gap-1.5 flex-wrap">
                <button
                  :if={@registry_entry && @registry_entry.id in [:akai_mpc_live_ii]}
                  phx-click="load_preset"
                  phx-value-preset="mpc"
                  class={[
                    "px-2 py-1 text-xs rounded border transition-colors",
                    if(@selected_preset == "mpc",
                      do: "bg-purple-700 border-purple-600 text-white",
                      else: "border-gray-700 text-gray-400 hover:border-purple-600 hover:text-white"
                    )
                  ]}
                >
                  MPC Preset
                </button>
                <button
                  :if={@registry_entry && @registry_entry.id == :mvave_standard}
                  phx-click="load_preset"
                  phx-value-preset="mvave"
                  class={[
                    "px-2 py-1 text-xs rounded border transition-colors",
                    if(@selected_preset == "mvave",
                      do: "bg-purple-700 border-purple-600 text-white",
                      else: "border-gray-700 text-gray-400 hover:border-purple-600 hover:text-white"
                    )
                  ]}
                >
                  M-VAVE Preset
                </button>
                <button
                  phx-click="load_preset"
                  phx-value-preset="generic"
                  class={[
                    "px-2 py-1 text-xs rounded border transition-colors",
                    if(@selected_preset == "generic",
                      do: "bg-gray-700 border-gray-600 text-white",
                      else: "border-gray-700 text-gray-500 hover:border-gray-500 hover:text-white"
                    )
                  ]}
                >
                  Generic
                </button>
              </div>
            </div>

            <%!-- Per-controller mappings list --%>
            <div class="px-3 pb-4 border-t border-gray-800/40 pt-3 flex-1">
              <p class="text-[10px] text-gray-500 uppercase tracking-wider mb-2">
                Mappings ({length(@controller_mappings)})
              </p>

              <div :if={@controller_mappings == []} class="text-xs text-gray-700 italic">
                No mappings for this controller yet.
              </div>

              <div class="space-y-0.5">
                <%= for mapping <- @controller_mappings do %>
                  <div class="flex items-center gap-2 py-1 group">
                    <span class={category_dot_class(action_category(mapping.action))} />
                    <span class="flex-1 text-xs text-gray-300 truncate">{format_action(mapping.action)}</span>
                    <span class="text-[10px] font-mono text-gray-600">
                      {format_midi_type(mapping.midi_type)}{mapping.number}
                    </span>
                    <button
                      phx-click="delete_mapping"
                      phx-value-id={mapping.id}
                      class="opacity-0 group-hover:opacity-100 text-[10px] text-red-600 hover:text-red-400 transition-opacity"
                    >
                      ×
                    </button>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- ============================================================ --%>
      <%!-- MIDI Monitor strip (collapsible) --%>
      <%!-- ============================================================ --%>
      <div class="border-t border-gray-800 bg-gray-950 flex-shrink-0">
        <div class="flex items-center gap-3 px-4 py-2 cursor-pointer select-none" phx-click="toggle_monitor">
          <div class={["w-2 h-2 rounded-full", if(@monitor_listening, do: "bg-green-400 animate-pulse", else: "bg-gray-700")]} />
          <span class="text-xs font-medium text-gray-400">MIDI Monitor</span>
          <span :if={@midi_monitor != []} class="text-[10px] text-gray-600">({length(@midi_monitor)} events)</span>
          <div class="flex-1" />
          <div class="flex items-center gap-2">
            <button
              class={["text-xs px-2 py-0.5 rounded transition-colors", if(@monitor_listening, do: "bg-red-900/50 text-red-400 hover:bg-red-900", else: "bg-gray-800 text-gray-400 hover:bg-gray-700")]}
              phx-click={if(@monitor_listening, do: "toggle_monitor_listen", else: "toggle_monitor_listen")}
            >
              {if @monitor_listening, do: "Stop", else: "Start"}
            </button>
            <button :if={@midi_monitor != []} class="text-xs text-gray-600 hover:text-gray-400 transition-colors" phx-click="clear_monitor">
              Clear
            </button>
            <svg class={["w-3 h-3 text-gray-600 transition-transform", if(@monitor_expanded, do: "rotate-180", else: "")]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
            </svg>
          </div>
        </div>

        <div :if={@monitor_expanded} class="border-t border-gray-800/50 overflow-y-auto" style="max-height: 180px;">
          <div :if={@midi_monitor == [] && @monitor_listening} class="px-4 py-3 text-xs text-green-400 flex items-center gap-2">
            <span class="w-1.5 h-1.5 rounded-full bg-green-400 animate-pulse inline-block" />
            Listening for MIDI input...
          </div>
          <div :if={@midi_monitor == [] && !@monitor_listening} class="px-4 py-3 text-xs text-gray-600 italic">
            Click Start to begin capturing MIDI events.
          </div>
          <div class="divide-y divide-gray-800/30">
            <div
              :for={entry <- Enum.take(@midi_monitor, 50)}
              class="flex items-center gap-3 px-4 py-1 font-mono text-[10px] hover:bg-gray-900/40"
            >
              <span class={["px-1.5 py-0.5 rounded text-[9px] uppercase font-bold flex-shrink-0", monitor_type_class(entry.type)]}>
                {format_midi_type(entry.type)}
              </span>
              <span class="text-gray-500 w-6 text-right flex-shrink-0">{entry.channel}</span>
              <span class="text-gray-400 w-8 text-right flex-shrink-0">#{entry.number}</span>
              <div class="flex-1 flex items-center gap-2 min-w-0">
                <div class="flex-1 bg-gray-800 rounded-full h-1 overflow-hidden">
                  <div class="h-full bg-cyan-500/60 rounded-full" style={"width: #{round((entry.value || 0) / 127 * 100)}%"} />
                </div>
                <span class="text-gray-600 w-7 text-right flex-shrink-0">{entry.value || 0}</span>
              </div>
              <span class="text-gray-700 truncate max-w-[70px] flex-shrink-0">{entry.port_id}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # SVG Controller Component
  # ---------------------------------------------------------------------------

  defp controller_svg(%{registry: %{id: :akai_mpc_live_ii}} = assigns) do
    ~H"""
    <div class="rounded-lg overflow-hidden border border-gray-800">
      <svg viewBox="0 0 360 230" xmlns="http://www.w3.org/2000/svg" class="w-full">
        <%!-- Body --%>
        <rect width="360" height="230" rx="10" fill="#1a1a2e" />
        <rect x="2" y="2" width="356" height="226" rx="9" fill="none" stroke="#374151" stroke-width="1" />

        <%!-- Screen --%>
        <rect x="8" y="8" width="228" height="84" rx="4" fill="#0d1117" stroke="#374151" stroke-width="1" />
        <text x="122" y="52" text-anchor="middle" fill="#374151" font-size="11" font-family="monospace">MPC Live II</text>
        <text x="122" y="66" text-anchor="middle" fill="#1e3a5f" font-size="8" font-family="monospace">AKAI Professional</text>

        <%!-- Transport buttons (top right) --%>
        <%= for {btn, i} <- Enum.with_index(@registry.buttons) do %>
          <% bx = 245 + rem(i, 2) * 54 %>
          <% by = 14 + div(i, 2) * 22 %>
          <% mapped = Enum.any?(@mappings, &(&1.midi_type == :cc && &1.number == btn.cc)) %>
          <rect x={bx} y={by} width="46" height="16" rx="3"
            fill={if mapped, do: "#4c1d95", else: "#1f2937"}
            stroke={if mapped, do: "#7c3aed", else: "#374151"}
            stroke-width="1" />
          <text x={bx + 23} y={by + 11} text-anchor="middle" fill={if mapped, do: "#c4b5fd", else: "#6b7280"} font-size="7" font-family="sans-serif">
            {btn.label}
          </text>
        <% end %>

        <%!-- Pad grid (4x4, bottom left) --%>
        <%= for pad <- @registry.pads do %>
          <% px = 8 + pad.col * 40 %>
          <%!-- MPC pads: row 0 = top of grid, row 3 = bottom (displayed) --%>
          <% py = 100 + (3 - div(pad.index, 4)) * 32 %>
          <% mapped = pad_mapped?(@mappings, pad.index) %>
          <% selected = @selected_element && @selected_element.kind == :pad && @selected_element.index == pad.index %>
          <rect
            x={px} y={py} width="36" height="28" rx="3"
            fill={cond do
              selected -> "#ca8a04"
              mapped -> "#581c87"
              true -> "#111827"
            end}
            stroke={cond do
              selected -> "#fbbf24"
              mapped -> "#7c3aed"
              true -> "#374151"
            end}
            stroke-width={if selected || mapped, do: "1.5", else: "0.5"}
            class="cursor-pointer hover:brightness-125 transition-all"
            phx-click="select_element"
            phx-value-kind="pad"
            phx-value-index={pad.index}
          />
          <text x={px + 18} y={py + 17} text-anchor="middle"
            fill={cond do
              selected -> "#fef08a"
              mapped -> "#c4b5fd"
              true -> "#374151"
            end}
            font-size="7" font-family="monospace" class="pointer-events-none"
          >{pad.index + 1}</text>
        <% end %>

        <%!-- Q-Link knobs (right of pads) --%>
        <%= for {knob, i} <- Enum.with_index(@registry.knobs) do %>
          <% kx = 174 + rem(i, 3) * 30 %>
          <% ky = 118 + div(i, 3) * 34 %>
          <% mapped = knob_mapped?(@mappings, knob.cc) %>
          <% selected = @selected_element && @selected_element.kind == :knob && @selected_element.index == i %>
          <circle cx={kx} cy={ky} r="11"
            fill={cond do
              selected -> "#ca8a04"
              mapped -> "#1e3a5f"
              true -> "#111827"
            end}
            stroke={cond do
              selected -> "#fbbf24"
              mapped -> "#3b82f6"
              true -> "#374151"
            end}
            stroke-width={if selected || mapped, do: "1.5", else: "0.75"}
            class="cursor-pointer hover:brightness-125 transition-all"
            phx-click="select_element"
            phx-value-kind="knob"
            phx-value-index={i}
          />
          <text x={kx} y={ky + 4} text-anchor="middle"
            fill={if mapped || selected, do: "#93c5fd", else: "#374151"}
            font-size="6" font-family="monospace" class="pointer-events-none"
          >{knob.label}</text>
        <% end %>

        <%!-- Bottom label --%>
        <text x="180" y="224" text-anchor="middle" fill="#1f2937" font-size="8" font-family="sans-serif">Click pads or knobs to assign MIDI</text>
      </svg>
    </div>
    """
  end

  defp controller_svg(%{registry: %{id: :mvave_standard}} = assigns) do
    ~H"""
    <div class="rounded-lg overflow-hidden border border-gray-800">
      <svg viewBox="0 0 300 210" xmlns="http://www.w3.org/2000/svg" class="w-full">
        <%!-- Body --%>
        <rect width="300" height="210" rx="8" fill="#0d1117" />
        <rect x="2" y="2" width="296" height="206" rx="7" fill="none" stroke="#374151" stroke-width="1" />

        <%!-- Device label --%>
        <text x="150" y="14" text-anchor="middle" fill="#374151" font-size="9" font-family="sans-serif">M-VAVE</text>

        <%!-- Knobs row 1 (Rate/Tempo/Swing/Latch) --%>
        <text x="8" y="34" fill="#374151" font-size="7" font-family="sans-serif">ROW 1</text>
        <%= for knob <- Enum.filter(@registry.knobs, &(&1.row == 0)) do %>
          <% kx = 30 + knob.index * 62 %>
          <% mapped = knob_mapped?(@mappings, knob.cc) %>
          <% selected = @selected_element && @selected_element.kind == :knob && @selected_element.index == knob.index %>
          <circle cx={kx} cy="52" r="18"
            fill={cond do
              selected -> "#ca8a04"
              mapped -> "#1e3a5f"
              true -> "#111827"
            end}
            stroke={cond do
              selected -> "#fbbf24"
              mapped -> "#3b82f6"
              true -> "#374151"
            end}
            stroke-width={if selected || mapped, do: "2", else: "1"}
            class="cursor-pointer hover:brightness-125 transition-all"
            phx-click="select_element"
            phx-value-kind="knob"
            phx-value-index={knob.index}
          />
          <circle cx={kx} cy="36" r="2" fill={if mapped || selected, do: "#93c5fd", else: "#374151"} class="pointer-events-none" />
          <text x={kx} y="56" text-anchor="middle" fill={if mapped || selected, do: "#93c5fd", else: "#4b5563"} font-size="6.5" font-family="sans-serif" class="pointer-events-none">
            {knob.label}
          </text>
          <text x={kx} y="65" text-anchor="middle" fill="#1f2937" font-size="5.5" font-family="monospace" class="pointer-events-none">CC{knob.cc}</text>
        <% end %>

        <%!-- Knobs row 2 --%>
        <text x="8" y="90" fill="#374151" font-size="7" font-family="sans-serif">ROW 2</text>
        <%= for knob <- Enum.filter(@registry.knobs, &(&1.row == 1)) do %>
          <% kx = 30 + (knob.index - 4) * 62 %>
          <% mapped = knob_mapped?(@mappings, knob.cc) %>
          <% selected = @selected_element && @selected_element.kind == :knob && @selected_element.index == knob.index %>
          <circle cx={kx} cy="108" r="18"
            fill={cond do
              selected -> "#ca8a04"
              mapped -> "#1e3a5f"
              true -> "#111827"
            end}
            stroke={cond do
              selected -> "#fbbf24"
              mapped -> "#3b82f6"
              true -> "#374151"
            end}
            stroke-width={if selected || mapped, do: "2", else: "1"}
            class="cursor-pointer hover:brightness-125 transition-all"
            phx-click="select_element"
            phx-value-kind="knob"
            phx-value-index={knob.index}
          />
          <circle cx={kx} cy="92" r="2" fill={if mapped || selected, do: "#93c5fd", else: "#374151"} class="pointer-events-none" />
          <text x={kx} y="112" text-anchor="middle" fill={if mapped || selected, do: "#93c5fd", else: "#4b5563"} font-size="6.5" font-family="sans-serif" class="pointer-events-none">
            {knob.label}
          </text>
        <% end %>

        <%!-- Pad grid (4x4) --%>
        <%= for pad <- @registry.pads do %>
          <% px = 8 + pad.col * 37 %>
          <% py = 132 + (3 - div(pad.index, 4)) * 18 %>
          <% mapped = pad_mapped?(@mappings, pad.index) %>
          <% selected = @selected_element && @selected_element.kind == :pad && @selected_element.index == pad.index %>
          <rect
            x={px} y={py} width="33" height="14" rx="2"
            fill={cond do
              selected -> "#ca8a04"
              mapped -> "#581c87"
              true -> "#111827"
            end}
            stroke={cond do
              selected -> "#fbbf24"
              mapped -> "#7c3aed"
              true -> "#374151"
            end}
            stroke-width={if selected || mapped, do: "1.5", else: "0.5"}
            class="cursor-pointer hover:brightness-125 transition-all"
            phx-click="select_element"
            phx-value-kind="pad"
            phx-value-index={pad.index}
          />
          <text x={px + 16} y={py + 10} text-anchor="middle"
            fill={if mapped || selected, do: "#c4b5fd", else: "#374151"}
            font-size="5.5" font-family="monospace" class="pointer-events-none"
          >{pad.index + 1}</text>
        <% end %>

        <%!-- Transport buttons (bottom row) --%>
        <%= for {btn, i} <- Enum.with_index(@registry.buttons) do %>
          <% bx = 155 + i * 36 %>
          <% mapped = Enum.any?(@mappings, &(&1.midi_type == :cc && &1.number == btn.cc)) %>
          <rect x={bx} y="194" width="30" height="12" rx="2"
            fill={if mapped, do: "#1c1917", else: "#111827"}
            stroke={if mapped, do: "#57534e", else: "#374151"}
            stroke-width="0.75" />
          <text x={bx + 15} y="203" text-anchor="middle" fill={if mapped, do: "#a8a29e", else: "#374151"} font-size="6" font-family="sans-serif">
            {btn.label}
          </text>
        <% end %>

        <text x="150" y="208" text-anchor="middle" fill="#1f2937" font-size="6" font-family="sans-serif">Click to assign MIDI</text>
      </svg>
    </div>
    """
  end

  defp controller_svg(assigns) do
    # Fallback for unrecognized controller - generic pad grid
    ~H"""
    <div class="rounded-lg bg-gray-900 border border-gray-800 p-3">
      <p class="text-[10px] text-gray-600 text-center mb-2">Generic controller — click pads to map</p>
      <div class="grid grid-cols-4 gap-1">
        <%= for i <- 0..15 do %>
          <% mapped = pad_mapped?(@mappings, i) %>
          <% selected = @selected_element && @selected_element.kind == :pad && @selected_element.index == i %>
          <button
            phx-click="select_element"
            phx-value-kind="pad"
            phx-value-index={i}
            class={[
              "aspect-square rounded text-[9px] font-mono transition-all",
              cond do
                selected -> "bg-yellow-500 text-black"
                mapped -> "bg-purple-700 text-white"
                true -> "bg-gray-800 text-gray-600 hover:bg-gray-700"
              end
            ]}
          >{i + 1}</button>
        <% end %>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolve_user_id(%{id: id}, _session) when is_integer(id), do: id

  defp resolve_user_id(_, session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _} <- SoundForge.Accounts.get_user_by_session_token(token) do
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

  defp extract_mapping_from_message(_), do: {nil, nil, nil}

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

  defp load_preset_mappings("mvave", user_id, _socket) do
    :mvave_standard
    |> MVAVE.default_mappings(user_id)
    |> Enum.map(&Mappings.create_mapping/1)
  end

  defp load_preset_mappings(preset, _user_id, _socket) do
    {:error, "Unknown preset: #{preset}"}
  end

  defp pad_mapped?(mappings, pad_index) do
    Enum.any?(mappings, fn m ->
      m.midi_type == :note_on &&
        m.number == 36 + pad_index
    end)
  end

  defp knob_mapped?(mappings, cc) do
    Enum.any?(mappings, fn m -> m.midi_type == :cc && m.number == cc end)
  end

  defp actions_by_category do
    [
      {:transport, "Transport", [:play, :stop, :next_track, :prev_track, :seek, :bpm_tap]},
      {:dj, "DJ", [:dj_play, :dj_cue, :dj_crossfader, :dj_loop_toggle, :dj_loop_size, :dj_pitch]},
      {:pads, "Pads", [:pad_trigger, :pad_volume, :pad_pitch, :pad_velocity, :pad_master_volume]},
      {:stems, "Stems", [:stem_solo, :stem_mute, :stem_volume]}
    ]
  end

  defp osc_addresses do
    [
      {"/transport/play", "Play/Stop toggle"},
      {"/transport/stop", "Stop playback"},
      {"/transport/next", "Next track"},
      {"/transport/prev", "Previous track"},
      {"/stem/N/volume", "Stem volume (0.0–1.0)"},
      {"/stem/N/mute", "Mute stem (0/1)"},
      {"/stem/N/solo", "Solo stem (0/1)"}
    ]
  end

  defp action_category(action)
       when action in [:play, :stop, :next_track, :prev_track, :seek, :bpm_tap],
       do: :transport

  defp action_category(action)
       when action in [:dj_play, :dj_cue, :dj_crossfader, :dj_loop_toggle, :dj_loop_size, :dj_pitch],
       do: :dj

  defp action_category(action)
       when action in [:pad_trigger, :pad_volume, :pad_pitch, :pad_velocity, :pad_master_volume],
       do: :pads

  defp action_category(action) when action in [:stem_solo, :stem_mute, :stem_volume], do: :stems
  defp action_category(_), do: :other

  defp mapping_for_action(mappings, action), do: Enum.find(mappings, &(&1.action == action))

  defp count_mapped_actions(mappings, actions) do
    Enum.count(actions, &mapping_for_action(mappings, &1))
  end

  defp shorten_device_name(name) when is_binary(name) do
    cond do
      String.length(name) <= 16 -> name
      String.contains?(String.downcase(name), "mpc") -> "MPC"
      String.contains?(String.downcase(name), "m-vave") -> "M-VAVE"
      true -> String.slice(name, 0, 14) <> "…"
    end
  end

  defp format_action(action) when is_atom(action) do
    action |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp format_midi_type(:cc), do: "CC"
  defp format_midi_type(:note_on), do: "Note"
  defp format_midi_type(:note_off), do: "NoteOff"
  defp format_midi_type(other) when is_atom(other), do: Atom.to_string(other)

  defp category_pill_class(:transport), do: "inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium bg-blue-900/60 text-blue-300"
  defp category_pill_class(:dj), do: "inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium bg-cyan-900/60 text-cyan-300"
  defp category_pill_class(:pads), do: "inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium bg-purple-900/60 text-purple-300"
  defp category_pill_class(:stems), do: "inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium bg-green-900/60 text-green-300"
  defp category_pill_class(_), do: "inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium bg-gray-800 text-gray-400"

  defp category_dot_class(:transport), do: "w-1.5 h-1.5 rounded-full bg-blue-500 flex-shrink-0"
  defp category_dot_class(:dj), do: "w-1.5 h-1.5 rounded-full bg-cyan-500 flex-shrink-0"
  defp category_dot_class(:pads), do: "w-1.5 h-1.5 rounded-full bg-purple-500 flex-shrink-0"
  defp category_dot_class(:stems), do: "w-1.5 h-1.5 rounded-full bg-green-500 flex-shrink-0"
  defp category_dot_class(_), do: "w-1.5 h-1.5 rounded-full bg-gray-600 flex-shrink-0"

  defp type_label(:usb), do: "USB"
  defp type_label(:network), do: "RTP-MIDI"
  defp type_label(:virtual), do: "Virtual"
  defp type_label(_), do: "MIDI"

  defp type_badge_class(:usb), do: "inline-flex text-[9px] px-1 py-0 rounded bg-amber-900/50 text-amber-400 border border-amber-800/50"
  defp type_badge_class(:network), do: "inline-flex text-[9px] px-1 py-0 rounded bg-blue-900/50 text-blue-400 border border-blue-800/50"
  defp type_badge_class(_), do: "inline-flex text-[9px] px-1 py-0 rounded bg-gray-800 text-gray-500 border border-gray-700"

  defp direction_label(:input), do: "In"
  defp direction_label(:output), do: "Out"
  defp direction_label(:duplex), do: "I/O"
  defp direction_label(_), do: "?"

  defp direction_badge_class(:input), do: "inline-flex text-[9px] px-1 py-0 rounded bg-green-900/40 text-green-400"
  defp direction_badge_class(:output), do: "inline-flex text-[9px] px-1 py-0 rounded bg-gray-800 text-gray-500"
  defp direction_badge_class(:duplex), do: "inline-flex text-[9px] px-1 py-0 rounded bg-emerald-900/50 text-emerald-400"
  defp direction_badge_class(_), do: "inline-flex text-[9px] px-1 py-0 rounded bg-gray-800 text-gray-600"

  defp status_label(:connected), do: "connected"
  defp status_label(:available), do: "available"
  defp status_label(:disconnected), do: "disconnected"
  defp status_label(_), do: "unknown"

  defp monitor_type_class(:cc), do: "bg-amber-900/60 text-amber-300"
  defp monitor_type_class(:note_on), do: "bg-green-900/60 text-green-300"
  defp monitor_type_class(:note_off), do: "bg-red-900/60 text-red-400"
  defp monitor_type_class(_), do: "bg-gray-800 text-gray-500"

  defp build_monitor_entry(port_id, message) do
    type = Map.get(message, :type, :unknown)
    channel = Map.get(message, :channel, 0)
    data = Map.get(message, :data, %{})
    number = Map.get(data, :number, Map.get(data, :controller, Map.get(data, :note, 0))) || 0
    value = Map.get(data, :value, Map.get(data, :velocity, 0)) || 0

    %{port_id: port_id, type: type, channel: channel, number: number, value: value}
  end
end
