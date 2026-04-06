defmodule SoundForgeWeb.Live.Components.MidiMonitorComponent do
  @moduledoc """
  Floating MIDI Monitor LiveComponent — always available from any tab.

  Shows raw MIDI events (Note On/Off, CC, SysEx, clock) from all connected
  devices. Supports two capture modes:

    * **Manual**: Click Start/Stop to capture a snapshot.
    * **Tail** (tailf): Continuously streams events in real-time — events
      are pushed from the parent LiveView via `send_update/3`.

  ## Usage

      <.live_component
        module={SoundForgeWeb.Live.Components.MidiMonitorComponent}
        id="midi-monitor"
        open={@midi_monitor_open}
        listening={@midi_monitor_listening}
        tailf={@midi_tailf}
        events={@midi_raw_log}
      />

  The parent LiveView must:
    1. Subscribe to `Dispatcher` PubSub when `listening` is true
    2. Forward `{:midi_message, port_id, msg}` via `send_update(MidiMonitorComponent, id: "midi-monitor", new_event: event)`
  """
  use SoundForgeWeb, :live_component

  @max_events 200

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:events, [])
     |> assign(:filter, :all)
     |> assign(:scroll_lock, true)}
  end

  @impl true
  def update(%{new_event: event} = _assigns, socket) do
    events = [event | socket.assigns.events] |> Enum.take(@max_events)
    {:ok, assign(socket, :events, events)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:open, assigns[:open] || false)
     |> assign(:listening, assigns[:listening] || false)
     |> assign(:tailf, assigns[:tailf] || false)
     |> assign(:events, assigns[:events] || socket.assigns.events)}
  end

  @impl true
  def handle_event("set_filter", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, :filter, String.to_existing_atom(filter))}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, :events, [])}
  end

  def handle_event("toggle_scroll_lock", _params, socket) do
    {:noreply, update(socket, :scroll_lock, &(!&1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      :if={@open}
      id="midi-monitor-panel"
      class="fixed bottom-16 right-4 z-50 w-96 bg-gray-900 border border-gray-700 rounded-xl shadow-2xl flex flex-col"
      style="max-height: 480px;"
    >
      <%!-- Header --%>
      <div class="flex items-center justify-between px-3 py-2 border-b border-gray-700 rounded-t-xl bg-gray-800/50">
        <div class="flex items-center gap-2">
          <div class={[
            "w-2 h-2 rounded-full transition-all",
            if(@listening, do: "bg-green-400 animate-pulse", else: "bg-gray-600")
          ]} />
          <span class="text-xs font-semibold text-gray-300 uppercase tracking-wider">MIDI Monitor</span>
          <span :if={@tailf} class="text-[9px] px-1.5 py-0.5 bg-green-900/50 text-green-400 rounded font-mono">
            LIVE
          </span>
        </div>
        <div class="flex items-center gap-1">
          <button
            phx-click="toggle_midi_monitor_listen"
            phx-target={@myself}
            class={[
              "text-[10px] px-2 py-0.5 rounded transition-colors font-medium",
              if(@listening, do: "bg-red-900/50 text-red-400 hover:bg-red-900", else: "bg-gray-700 text-gray-400 hover:bg-gray-600")
            ]}
            phx-click="toggle_midi_monitor_listen"
          >
            {if @listening, do: "Stop", else: "Start"}
          </button>
          <button
            phx-click="toggle_midi_tailf"
            class={[
              "text-[10px] px-2 py-0.5 rounded transition-colors font-medium",
              if(@tailf, do: "bg-purple-900/50 text-purple-400", else: "bg-gray-700 text-gray-500 hover:bg-gray-600")
            ]}
            title="Toggle tail -f mode (continuous live stream)"
          >
            tailf
          </button>
          <button
            phx-click="clear"
            phx-target={@myself}
            class="text-[10px] text-gray-600 hover:text-gray-400 transition-colors px-1"
          >
            Clear
          </button>
          <button
            phx-click="toggle_midi_monitor"
            class="text-gray-600 hover:text-white transition-colors ml-1"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>

      <%!-- Filter row --%>
      <div class="flex gap-1 px-3 py-1.5 border-b border-gray-800">
        <%= for {label, val} <- [{"All", :all}, {"Note", :note}, {"CC", :cc}, {"Clock", :clock}, {"Other", :other}] do %>
          <button
            phx-click="set_filter"
            phx-value-filter={val}
            phx-target={@myself}
            class={[
              "text-[9px] px-2 py-0.5 rounded transition-colors",
              if(@filter == val, do: "bg-purple-600 text-white", else: "bg-gray-800 text-gray-500 hover:bg-gray-700")
            ]}
          >
            {label}
          </button>
        <% end %>
        <div class="ml-auto flex items-center gap-1">
          <span class="text-[9px] text-gray-600">{length(@events)} events</span>
        </div>
      </div>

      <%!-- Event list --%>
      <div
        id="midi-monitor-events"
        class="flex-1 overflow-y-auto font-mono text-[10px]"
        phx-hook="MidiMonitorScroll"
        data-tailf={to_string(@tailf)}
        style="max-height: 340px;"
      >
        <div :if={@events == [] && !@listening} class="px-4 py-6 text-center text-gray-600">
          Click Start to capture MIDI events
        </div>
        <div :if={@events == [] && @listening} class="px-4 py-3 text-center text-green-500/60 flex items-center justify-center gap-2">
          <span class="inline-block w-2 h-2 bg-green-500 rounded-full animate-pulse" />
          Waiting for MIDI events...
        </div>
        <%= for event <- filter_events(@events, @filter) do %>
          <div class={[
            "flex items-start gap-2 px-3 py-0.5 border-b border-gray-800/40 hover:bg-gray-800/30",
            event_row_class(event.type)
          ]}>
            <span class="text-gray-600 shrink-0 w-16">{event.time}</span>
            <span class={["shrink-0 w-14 font-medium", event_type_class(event.type)]}>
              {event.type}
            </span>
            <span class="text-gray-500 shrink-0 w-6">CH{event.channel}</span>
            <span class="text-gray-300 flex-1 truncate">{event.label}</span>
            <span class="text-gray-600 shrink-0 w-8 text-right">{event.value}</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp filter_events(events, :all), do: events
  defp filter_events(events, filter), do: Enum.filter(events, &(&1.type == to_string(filter)))

  defp event_row_class("note_on"), do: "bg-purple-950/20"
  defp event_row_class("note_off"), do: "bg-gray-900/10"
  defp event_row_class("cc"), do: "bg-blue-950/20"
  defp event_row_class("clock"), do: "bg-gray-900/5"
  defp event_row_class(_), do: ""

  defp event_type_class("note_on"), do: "text-purple-400"
  defp event_type_class("note_off"), do: "text-gray-500"
  defp event_type_class("cc"), do: "text-blue-400"
  defp event_type_class("clock"), do: "text-gray-700"
  defp event_type_class("sysex"), do: "text-yellow-500"
  defp event_type_class(_), do: "text-gray-400"
end
