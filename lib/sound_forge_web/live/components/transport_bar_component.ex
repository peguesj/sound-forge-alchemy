defmodule SoundForgeWeb.Live.Components.TransportBarComponent do
  @moduledoc """
  SMPTE transport bar component -- professional audio transport controls.

  Renders a fixed-bottom transport bar with:
  - SMPTE timecode display (HH:MM:SS:FF) in monospaced green-on-dark
  - Transport buttons: rewind-to-start, rewind, stop, play/pause, fast-forward, record (DAW only)
  - Progress/scrub bar (clickable timeline)
  - BPM display
  - Loop toggle with in/out points
  - Master volume slider
  - Track info (title, artist)

  Modes based on `nav_tab`:
  - `:daw`     -- record button, time signature, zoom controls
  - `:dj`      -- deck selector, crossfader position indicator
  - `:library` -- simple playback with SMPTE timecode
  """
  use SoundForgeWeb, :live_component

  @default_fps 30
  @default_bpm 120.0
  @default_time_sig "4/4"

  # -- Lifecycle --

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:playing, false)
     |> assign(:recording, false)
     |> assign(:current_time, 0.0)
     |> assign(:duration, 0.0)
     |> assign(:bpm, @default_bpm)
     |> assign(:time_signature, @default_time_sig)
     |> assign(:loop_enabled, false)
     |> assign(:loop_in, nil)
     |> assign(:loop_out, nil)
     |> assign(:master_volume, 80)
     |> assign(:fps, @default_fps)
     |> assign(:active_deck, 1)
     |> assign(:zoom_level, 1.0)
     |> assign(:track_title, nil)
     |> assign(:track_artist, nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, :id, assigns[:id])
    socket = assign(socket, :nav_tab, assigns[:nav_tab] || :library)

    # Accept track info if provided
    socket =
      if assigns[:track] do
        track = assigns[:track]

        bpm =
          case assigns[:analysis] do
            %SoundForge.Music.AnalysisResult{tempo: t} when is_number(t) -> t
            %{tempo: t} when is_number(t) -> t
            _ -> socket.assigns.bpm
          end

        socket
        |> assign(:track_title, track.title)
        |> assign(:track_artist, track.artist)
        |> assign(:bpm, bpm)
      else
        socket
      end

    # Accept duration override (e.g. from player_ready)
    socket =
      if assigns[:duration] do
        assign(socket, :duration, assigns[:duration])
      else
        socket
      end

    {:ok, socket}
  end

  # -- Events --

  @impl true
  def handle_event("transport_play", _params, socket) do
    new_state = !socket.assigns.playing

    {:noreply,
     socket
     |> assign(:playing, new_state)
     |> assign(:recording, if(!new_state, do: false, else: socket.assigns.recording))
     |> push_event("transport_command", %{action: if(new_state, do: "play", else: "pause")})}
  end

  @impl true
  def handle_event("transport_stop", _params, socket) do
    {:noreply,
     socket
     |> assign(:playing, false)
     |> assign(:recording, false)
     |> assign(:current_time, 0.0)
     |> push_event("transport_command", %{action: "stop"})}
  end

  @impl true
  def handle_event("transport_rewind_start", _params, socket) do
    {:noreply,
     socket
     |> assign(:current_time, 0.0)
     |> push_event("transport_command", %{action: "rewind_start"})}
  end

  @impl true
  def handle_event("transport_rewind", _params, socket) do
    new_time = max(socket.assigns.current_time - 5.0, 0.0)

    {:noreply,
     socket
     |> assign(:current_time, new_time)
     |> push_event("transport_command", %{action: "seek", time: new_time})}
  end

  @impl true
  def handle_event("transport_ff", _params, socket) do
    new_time = min(socket.assigns.current_time + 5.0, socket.assigns.duration)

    {:noreply,
     socket
     |> assign(:current_time, new_time)
     |> push_event("transport_command", %{action: "seek", time: new_time})}
  end

  @impl true
  def handle_event("transport_record", _params, socket) do
    # Only available in DAW mode
    if socket.assigns.nav_tab == :daw do
      new_state = !socket.assigns.recording

      {:noreply,
       socket
       |> assign(:recording, new_state)
       |> assign(:playing, if(new_state, do: true, else: socket.assigns.playing))
       |> push_event("transport_command", %{action: "record", enabled: new_state})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("transport_seek", %{"position" => position}, socket) do
    pos = parse_float(position)
    time = pos * socket.assigns.duration

    {:noreply,
     socket
     |> assign(:current_time, time)
     |> push_event("transport_command", %{action: "seek", time: time})}
  end

  @impl true
  def handle_event("transport_volume", %{"level" => level}, socket) do
    level_int = String.to_integer(level)

    {:noreply,
     socket
     |> assign(:master_volume, level_int)
     |> push_event("transport_command", %{action: "volume", level: level_int})}
  end

  @impl true
  def handle_event("toggle_loop", _params, socket) do
    new_state = !socket.assigns.loop_enabled

    socket =
      if new_state and is_nil(socket.assigns.loop_in) do
        # Set default loop points
        socket
        |> assign(:loop_in, 0.0)
        |> assign(:loop_out, socket.assigns.duration)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:loop_enabled, new_state)
     |> push_event("transport_command", %{
       action: "loop",
       enabled: new_state,
       loop_in: socket.assigns.loop_in,
       loop_out: socket.assigns.loop_out
     })}
  end

  @impl true
  def handle_event("set_loop_in", _params, socket) do
    {:noreply,
     socket
     |> assign(:loop_in, socket.assigns.current_time)
     |> push_event("transport_command", %{
       action: "loop_in",
       time: socket.assigns.current_time
     })}
  end

  @impl true
  def handle_event("set_loop_out", _params, socket) do
    {:noreply,
     socket
     |> assign(:loop_out, socket.assigns.current_time)
     |> push_event("transport_command", %{
       action: "loop_out",
       time: socket.assigns.current_time
     })}
  end

  @impl true
  def handle_event("select_deck", %{"deck" => deck}, socket) do
    {:noreply, assign(socket, :active_deck, String.to_integer(deck))}
  end

  @impl true
  def handle_event("zoom_in", _params, socket) do
    new_zoom = min(socket.assigns.zoom_level * 1.5, 16.0)

    {:noreply,
     socket
     |> assign(:zoom_level, new_zoom)
     |> push_event("transport_command", %{action: "zoom", level: new_zoom})}
  end

  @impl true
  def handle_event("zoom_out", _params, socket) do
    new_zoom = max(socket.assigns.zoom_level / 1.5, 0.25)

    {:noreply,
     socket
     |> assign(:zoom_level, new_zoom)
     |> push_event("transport_command", %{action: "zoom", level: new_zoom})}
  end

  @impl true
  def handle_event("transport_time_update", %{"time" => time}, socket) do
    {:noreply, assign(socket, :current_time, time)}
  end

  @impl true
  def handle_event("transport_duration", %{"duration" => duration}, socket) do
    {:noreply, assign(socket, :duration, duration)}
  end

  @impl true
  def handle_event("transport_bpm", %{"bpm" => bpm}, socket) do
    {:noreply, assign(socket, :bpm, bpm)}
  end

  # -- Template --

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"transport-bar-#{@id}"}
      phx-hook="TransportBar"
      phx-target={@myself}
      data-nav-tab={@nav_tab}
      data-fps={@fps}
      class="fixed bottom-0 left-0 right-0 z-40 bg-gray-950 border-t border-gray-800 select-none"
    >
      <div class="h-[72px] flex items-center px-4 gap-3">
        <%!-- Track Info Section --%>
        <div class="flex items-center gap-3 min-w-[160px] max-w-[200px]">
          <div class="truncate">
            <p class="text-sm font-medium text-gray-200 truncate">
              {@track_title || "No Track"}
            </p>
            <p class="text-xs text-gray-500 truncate">
              {@track_artist || "--"}
            </p>
          </div>
        </div>

        <div class="w-px h-10 bg-gray-800"></div>

        <%!-- SMPTE Timecode Display --%>
        <div class="flex items-center gap-2">
          <div
            id={"smpte-display-#{@id}"}
            class="bg-black rounded-md px-3 py-1.5 border border-gray-800 font-mono text-lg tracking-wider min-w-[170px] text-center"
            style="color: #00ff41; text-shadow: 0 0 8px rgba(0, 255, 65, 0.4), 0 0 2px rgba(0, 255, 65, 0.2); font-family: 'JetBrains Mono', 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;"
          >
            {format_smpte(@current_time, @fps)}
          </div>
          <div class="text-[10px] text-gray-600 leading-tight">
            <div>{@fps}fps</div>
            <div>SMPTE</div>
          </div>
        </div>

        <div class="w-px h-10 bg-gray-800"></div>

        <%!-- Transport Buttons --%>
        <div class="flex items-center gap-1">
          <%!-- Rewind to Start --%>
          <button
            phx-click="transport_rewind_start"
            phx-target={@myself}
            class="transport-btn w-9 h-9 rounded flex items-center justify-center bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white transition-colors"
            title="Rewind to start (Home)"
          >
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
              <path d="M6 6h2v12H6zm3.5 6l8.5 6V6z" />
            </svg>
          </button>

          <%!-- Rewind --%>
          <button
            phx-click="transport_rewind"
            phx-target={@myself}
            class="transport-btn w-9 h-9 rounded flex items-center justify-center bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white transition-colors"
            title="Rewind 5s"
          >
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
              <path d="M11 18V6l-8.5 6 8.5 6zm.5-6l8.5 6V6l-8.5 6z" />
            </svg>
          </button>

          <%!-- Stop --%>
          <button
            phx-click="transport_stop"
            phx-target={@myself}
            class="transport-btn w-9 h-9 rounded flex items-center justify-center bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white transition-colors"
            title="Stop"
          >
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
              <rect x="6" y="6" width="12" height="12" />
            </svg>
          </button>

          <%!-- Play/Pause --%>
          <button
            phx-click="transport_play"
            phx-target={@myself}
            class={"transport-btn w-11 h-11 rounded-lg flex items-center justify-center transition-colors " <>
              if(@playing, do: "bg-green-600 hover:bg-green-500 text-white shadow-lg shadow-green-900/30", else: "bg-gray-700 hover:bg-gray-600 text-gray-200 hover:text-white")}
            title={if @playing, do: "Pause (Space)", else: "Play (Space)"}
          >
            <svg :if={!@playing} class="w-5 h-5 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M8 5v14l11-7z" />
            </svg>
            <svg :if={@playing} class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
            </svg>
          </button>

          <%!-- Fast Forward --%>
          <button
            phx-click="transport_ff"
            phx-target={@myself}
            class="transport-btn w-9 h-9 rounded flex items-center justify-center bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white transition-colors"
            title="Fast forward 5s"
          >
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
              <path d="M4 18l8.5-6L4 6v12zm9-12v12l8.5-6L13 6z" />
            </svg>
          </button>

          <%!-- Record (DAW only) --%>
          <button
            :if={@nav_tab == :daw}
            phx-click="transport_record"
            phx-target={@myself}
            class={"transport-btn w-9 h-9 rounded flex items-center justify-center transition-colors " <>
              if(@recording, do: "bg-red-600 hover:bg-red-500 text-white animate-pulse", else: "bg-gray-800 hover:bg-gray-700 text-red-400 hover:text-red-300")}
            title="Record"
          >
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
              <circle cx="12" cy="12" r="7" />
            </svg>
          </button>
        </div>

        <div class="w-px h-10 bg-gray-800"></div>

        <%!-- Progress Scrub Bar --%>
        <div class="flex-1 flex items-center gap-2 min-w-[120px]">
          <span class="text-[10px] text-gray-500 font-mono min-w-[36px] text-right">
            {format_time_short(@current_time)}
          </span>
          <div class="flex-1 relative group cursor-pointer" id={"scrub-bar-#{@id}"}>
            <div class="h-1.5 bg-gray-800 rounded-full overflow-hidden group-hover:h-2.5 transition-all">
              <div
                class="h-full bg-gradient-to-r from-green-500 to-green-400 rounded-full transition-all"
                style={"width: #{progress_percent(@current_time, @duration)}%"}
              >
              </div>
            </div>
            <%!-- Loop markers overlay --%>
            <div
              :if={@loop_enabled and @loop_in && @loop_out && @duration > 0}
              class="absolute top-0 h-full rounded-full bg-purple-500/20 border-x border-purple-500/50 pointer-events-none"
              style={"left: #{progress_percent(@loop_in, @duration)}%; width: #{progress_percent(@loop_out - @loop_in, @duration)}%"}
            >
            </div>
          </div>
          <span class="text-[10px] text-gray-500 font-mono min-w-[36px]">
            {format_time_short(@duration)}
          </span>
        </div>

        <div class="w-px h-10 bg-gray-800"></div>

        <%!-- BPM Display --%>
        <div class="flex items-center gap-1.5">
          <div
            class="bg-black rounded px-2 py-1 border border-gray-800 font-mono text-sm min-w-[55px] text-center"
            style="color: #ffb000; text-shadow: 0 0 6px rgba(255, 176, 0, 0.3); font-family: 'JetBrains Mono', 'SF Mono', monospace;"
          >
            {format_bpm(@bpm)}
          </div>
          <span class="text-[10px] text-gray-600">BPM</span>
        </div>

        <%!-- Time Signature (DAW only) --%>
        <div :if={@nav_tab == :daw} class="flex items-center gap-1">
          <div class="bg-black rounded px-2 py-1 border border-gray-800 font-mono text-sm text-gray-400 min-w-[35px] text-center">
            {@time_signature}
          </div>
        </div>

        <%!-- Zoom Controls (DAW only) --%>
        <div :if={@nav_tab == :daw} class="flex items-center gap-0.5">
          <button
            phx-click="zoom_out"
            phx-target={@myself}
            class="w-7 h-7 rounded flex items-center justify-center bg-gray-800 hover:bg-gray-700 text-gray-400 hover:text-white text-xs transition-colors"
            title="Zoom out"
          >
            -
          </button>
          <span class="text-[10px] text-gray-500 min-w-[32px] text-center font-mono">
            {format_zoom(@zoom_level)}
          </span>
          <button
            phx-click="zoom_in"
            phx-target={@myself}
            class="w-7 h-7 rounded flex items-center justify-center bg-gray-800 hover:bg-gray-700 text-gray-400 hover:text-white text-xs transition-colors"
            title="Zoom in"
          >
            +
          </button>
        </div>

        <%!-- Deck Selector (DJ only) --%>
        <div :if={@nav_tab == :dj} class="flex items-center gap-1">
          <button
            :for={deck <- [1, 2]}
            phx-click="select_deck"
            phx-target={@myself}
            phx-value-deck={deck}
            class={"px-2 py-1 rounded text-xs font-medium transition-colors " <>
              if(@active_deck == deck,
                do: "bg-purple-600 text-white",
                else: "bg-gray-800 text-gray-400 hover:bg-gray-700 hover:text-gray-200")}
          >
            Deck {deck}
          </button>
        </div>

        <div class="w-px h-10 bg-gray-800"></div>

        <%!-- Loop Controls --%>
        <div class="flex items-center gap-1">
          <button
            phx-click="set_loop_in"
            phx-target={@myself}
            class={"w-7 h-7 rounded flex items-center justify-center text-[10px] font-bold transition-colors " <>
              if(@loop_enabled, do: "bg-purple-900/50 text-purple-400 hover:bg-purple-800/50", else: "bg-gray-800 text-gray-500 hover:bg-gray-700 hover:text-gray-300")}
            title="Set loop in point"
          >
            IN
          </button>
          <button
            phx-click="toggle_loop"
            phx-target={@myself}
            class={"w-8 h-7 rounded flex items-center justify-center transition-colors " <>
              if(@loop_enabled, do: "bg-purple-600 text-white", else: "bg-gray-800 text-gray-500 hover:bg-gray-700 hover:text-gray-300")}
            title={if @loop_enabled, do: "Disable loop", else: "Enable loop"}
          >
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
          </button>
          <button
            phx-click="set_loop_out"
            phx-target={@myself}
            class={"w-7 h-7 rounded flex items-center justify-center text-[10px] font-bold transition-colors " <>
              if(@loop_enabled, do: "bg-purple-900/50 text-purple-400 hover:bg-purple-800/50", else: "bg-gray-800 text-gray-500 hover:bg-gray-700 hover:text-gray-300")}
            title="Set loop out point"
          >
            OUT
          </button>
        </div>

        <div class="w-px h-10 bg-gray-800"></div>

        <%!-- Master Volume --%>
        <div class="flex items-center gap-1.5">
          <svg class="w-4 h-4 text-gray-500" fill="currentColor" viewBox="0 0 24 24">
            <path d="M3 9v6h4l5 5V4L7 9H3z" />
            <path :if={@master_volume > 0} d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z" />
            <path :if={@master_volume > 50} d="M19 12c0-3.53-2.04-6.58-5-8.07v2.09c2.12 1.33 3.5 3.59 3.5 5.98 0 2.39-1.38 4.65-3.5 5.98v2.09c2.96-1.49 5-4.54 5-8.07z" />
          </svg>
          <input
            type="range"
            min="0"
            max="100"
            value={@master_volume}
            phx-change="transport_volume"
            phx-target={@myself}
            name="level"
            class="w-20 h-1 accent-green-500 cursor-pointer"
            title={"Volume: #{@master_volume}%"}
          />
          <span class="text-[10px] text-gray-500 min-w-[24px] font-mono">{@master_volume}</span>
        </div>
      </div>
    </div>
    """
  end

  # -- Private Helpers --

  defp format_smpte(seconds, fps) when is_number(seconds) and is_number(fps) do
    total_frames = trunc(seconds * fps)
    frames = rem(total_frames, fps)
    total_seconds = div(total_frames, fps)
    secs = rem(total_seconds, 60)
    total_minutes = div(total_seconds, 60)
    mins = rem(total_minutes, 60)
    hours = div(total_minutes, 60)

    "#{pad2(hours)}:#{pad2(mins)}:#{pad2(secs)}:#{pad2(frames)}"
  end

  defp format_smpte(_, _), do: "00:00:00:00"

  defp format_time_short(seconds) when is_number(seconds) do
    total = trunc(seconds)
    mins = div(total, 60)
    secs = rem(total, 60)
    "#{mins}:#{pad2(secs)}"
  end

  defp format_time_short(_), do: "0:00"

  defp format_bpm(bpm) when is_number(bpm) do
    :erlang.float_to_binary(bpm / 1, decimals: 1)
  end

  defp format_bpm(_), do: "---.-"

  defp format_zoom(level) when is_number(level) do
    cond do
      level >= 1.0 -> "#{trunc(level)}x"
      true -> "#{:erlang.float_to_binary(level / 1, decimals: 1)}x"
    end
  end

  defp format_zoom(_), do: "1x"

  defp progress_percent(current, duration)
       when is_number(current) and is_number(duration) and duration > 0 do
    Float.round(current / duration * 100, 2)
  end

  defp progress_percent(_, _), do: 0

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: "#{n}"

  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(n) when is_number(n), do: n / 1
  defp parse_float(_), do: 0.0
end
