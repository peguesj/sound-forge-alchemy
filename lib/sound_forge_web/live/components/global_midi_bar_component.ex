defmodule SoundForgeWeb.Live.Components.GlobalMidiBarComponent do
  @moduledoc """
  Global MIDI status bar — always visible across all authenticated pages.

  Renders a thin fixed bar (bottom or top, per user settings) showing:
  - Active MIDI device name and input indicator
  - Real-time last MIDI event (note/CC/pressure with value visualization)
  - BPM from MIDI clock
  - MIDI monitor toggle (opens the floating MidiMonitorComponent overlay)
  - MIDI learn mode toggle
  - Sticky position badge (foot/head)

  ## Integration

  Each LiveView must:
    1. Include this component in its render function
    2. Subscribe to GlobalBroadcaster: `GlobalBroadcaster.subscribe()` in mount
    3. Forward events: `handle_info({:midi_global_event, port_id, msg}, socket)`
       → `send_update(GlobalMidiBarComponent, id: "global-midi-bar", midi_event: {port_id, msg})`

  Alternatively, the parent can use the `SoundForgeWeb.MidiBarMixin` module to
  get all of this wired up automatically.
  """

  use SoundForgeWeb, :live_component

  alias SoundForge.MIDI.DeviceManager

  @max_events 5

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:last_events, [])
     |> assign(:bpm, nil)
     |> assign(:active_device, nil)
     |> assign(:midi_monitor_open, false)
     |> assign(:midi_learn_active, false)
     |> assign(:position, "bottom")
     |> assign(:visible, true)}
  end

  @impl true
  def update(%{midi_event: {port_id, msg}} = _assigns, socket) do
    event = %{
      port_id: port_id,
      type: midi_type(msg),
      channel: Map.get(msg, :channel, 0),
      note_or_cc: Map.get(msg, :data1, 0),
      value: Map.get(msg, :data2, 0),
      at: System.monotonic_time(:millisecond)
    }

    events = [event | socket.assigns.last_events] |> Enum.take(@max_events)

    device_name =
      case DeviceManager.get_device_by_port(port_id) do
        %{name: name} -> name
        _ -> port_id
      end

    {:ok,
     socket
     |> assign(:last_events, events)
     |> assign(:active_device, device_name)}
  end

  def update(%{midi_bpm: bpm}, socket) do
    {:ok, assign(socket, :bpm, bpm)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign_new(:position, fn -> assigns[:position] || "bottom" end)
     |> assign_new(:visible, fn -> Map.get(assigns, :visible, true) end)
     |> assign(:midi_monitor_open, assigns[:midi_monitor_open] || socket.assigns.midi_monitor_open)
     |> assign(:midi_learn_active, assigns[:midi_learn_active] || socket.assigns.midi_learn_active)}
  end

  @impl true
  def handle_event("toggle_monitor", _params, socket) do
    open = !socket.assigns.midi_monitor_open
    send(self(), {:global_midi_bar, :toggle_monitor, open})
    {:noreply, assign(socket, :midi_monitor_open, open)}
  end

  def handle_event("toggle_learn", _params, socket) do
    active = !socket.assigns.midi_learn_active
    send(self(), {:global_midi_bar, :toggle_learn, active})
    {:noreply, assign(socket, :midi_learn_active, active)}
  end

  def handle_event("toggle_position", _params, socket) do
    pos = if socket.assigns.position == "bottom", do: "top", else: "bottom"
    send(self(), {:global_midi_bar, :set_position, pos})
    {:noreply, assign(socket, :position, pos)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="global-midi-bar"
      class={[
        "fixed left-0 right-0 z-40 h-9 flex items-center px-3 gap-3",
        "bg-gray-900/95 backdrop-blur border-gray-700/60",
        "text-xs text-gray-300 shadow-lg",
        bar_position_class(@position),
        if(!@visible, do: "hidden", else: "")
      ]}
      style="font-family: 'SF Mono', monospace;"
    >
      <%!-- MIDI icon + device --%>
      <div class="flex items-center gap-1.5 min-w-0">
        <div class={["w-2 h-2 rounded-full flex-shrink-0", if(@active_device, do: "bg-green-400 animate-pulse", else: "bg-gray-600")]}>
        </div>
        <span class="text-gray-500 font-semibold uppercase tracking-widest text-[9px]">MIDI</span>
        <span class="text-gray-300 truncate max-w-[120px]">
          {if @active_device, do: @active_device, else: "—"}
        </span>
      </div>

      <%!-- Divider --%>
      <div class="h-5 w-px bg-gray-700 flex-shrink-0"></div>

      <%!-- Last MIDI event --%>
      <div class="flex items-center gap-2 flex-1 min-w-0 overflow-hidden">
        <%= for event <- @last_events |> Enum.take(1) do %>
          <span class={["px-1.5 py-0.5 rounded text-[9px] font-bold", event_color_class(event.type)]}>
            {event.type}
          </span>
          <span class="text-gray-400 font-mono text-[10px]">
            Ch{event.channel + 1} · {event_label(event)} · <span class={value_color(event.value)}>{event.value}</span>
          </span>
          <%!-- Value bar --%>
          <div class="w-16 h-1.5 bg-gray-700 rounded-full overflow-hidden flex-shrink-0">
            <div
              class={["h-full rounded-full transition-all duration-75", value_bar_color(event.value)]}
              style={"width: #{trunc(event.value / 127 * 100)}%;"}
            ></div>
          </div>
        <% end %>
        <%= if @last_events == [] do %>
          <span class="text-gray-600 italic text-[10px]">no events yet</span>
        <% end %>
      </div>

      <%!-- BPM --%>
      <div :if={@bpm} class="flex items-center gap-1 flex-shrink-0">
        <span class="text-purple-400 font-bold font-mono text-[10px]">{Float.round(@bpm * 1.0, 1)} BPM</span>
      </div>

      <%!-- Monitor toggle --%>
      <button
        phx-click="toggle_monitor"
        phx-target={@myself}
        title={if @midi_monitor_open, do: "Close MIDI Monitor", else: "Open MIDI Monitor"}
        class={[
          "flex-shrink-0 px-2 py-0.5 rounded text-[9px] font-bold transition-colors",
          if(@midi_monitor_open,
            do: "bg-cyan-600 text-white",
            else: "bg-gray-800 text-gray-400 hover:bg-gray-700 hover:text-gray-200"
          )
        ]}
      >
        MON
      </button>

      <%!-- MIDI Learn toggle --%>
      <button
        phx-click="toggle_learn"
        phx-target={@myself}
        title={if @midi_learn_active, do: "Exit MIDI Learn", else: "Enter MIDI Learn"}
        class={[
          "flex-shrink-0 px-2 py-0.5 rounded text-[9px] font-bold transition-colors",
          if(@midi_learn_active,
            do: "bg-yellow-500 text-black animate-pulse",
            else: "bg-gray-800 text-gray-400 hover:bg-gray-700 hover:text-gray-200"
          )
        ]}
      >
        LEARN
      </button>

      <%!-- Position toggle --%>
      <button
        phx-click="toggle_position"
        phx-target={@myself}
        title={"Move bar to #{if @position == "bottom", do: "top", else: "bottom"}"}
        class="flex-shrink-0 text-gray-600 hover:text-gray-400 transition-colors"
      >
        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <%= if @position == "bottom" do %>
            <path stroke-linecap="round" stroke-linejoin="round" d="M5 15l7-7 7 7" />
          <% else %>
            <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
          <% end %>
        </svg>
      </button>
    </div>
    """
  end

  # -- Helpers --

  defp bar_position_class("top"), do: "top-0 border-b"
  defp bar_position_class(_), do: "bottom-0 border-t"

  defp midi_type(%{status: s}) when s in 0x80..0x8F, do: "NOTE OFF"
  defp midi_type(%{status: s}) when s in 0x90..0x9F, do: "NOTE ON"
  defp midi_type(%{status: s}) when s in 0xA0..0xAF, do: "POLY AT"
  defp midi_type(%{status: s}) when s in 0xB0..0xBF, do: "CC"
  defp midi_type(%{status: s}) when s in 0xC0..0xCF, do: "PROG"
  defp midi_type(%{status: s}) when s in 0xD0..0xDF, do: "CH AT"
  defp midi_type(%{status: s}) when s in 0xE0..0xEF, do: "PITCH"
  defp midi_type(%{status: 0xF8}), do: "CLOCK"
  defp midi_type(%{status: 0xFA}), do: "START"
  defp midi_type(%{status: 0xFC}), do: "STOP"
  defp midi_type(_), do: "SYS"

  defp event_label(%{type: "NOTE ON", note_or_cc: n}), do: "N#{n}"
  defp event_label(%{type: "NOTE OFF", note_or_cc: n}), do: "N#{n}"
  defp event_label(%{type: "CC", note_or_cc: cc}), do: "CC#{cc}"
  defp event_label(%{note_or_cc: n}), do: "##{n}"

  defp event_color_class("NOTE ON"), do: "bg-green-700/60 text-green-300"
  defp event_color_class("NOTE OFF"), do: "bg-gray-700/60 text-gray-400"
  defp event_color_class("CC"), do: "bg-blue-700/60 text-blue-300"
  defp event_color_class("POLY AT"), do: "bg-purple-700/60 text-purple-300"
  defp event_color_class("CH AT"), do: "bg-orange-700/60 text-orange-300"
  defp event_color_class("PITCH"), do: "bg-cyan-700/60 text-cyan-300"
  defp event_color_class(_), do: "bg-gray-700/60 text-gray-400"

  defp value_color(v) when v > 100, do: "text-green-400"
  defp value_color(v) when v > 50, do: "text-yellow-400"
  defp value_color(_), do: "text-gray-300"

  defp value_bar_color(v) when v > 100, do: "bg-green-500"
  defp value_bar_color(v) when v > 50, do: "bg-yellow-500"
  defp value_bar_color(_), do: "bg-blue-500"
end
