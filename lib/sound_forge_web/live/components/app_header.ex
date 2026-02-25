defmodule SoundForgeWeb.Live.Components.AppHeader do
  @moduledoc """
  Sticky header component for the app shell layout.
  Renders the logo, main navigation tabs, notification bell, and user dropdown.
  """
  use Phoenix.Component

  attr :current_scope, :map, default: nil
  attr :current_user_id, :any, default: nil
  attr :nav_tab, :atom, default: :library
  attr :nav_context, :atom, default: :all_tracks
  attr :midi_devices, :list, default: []
  attr :midi_bpm, :any, default: nil
  attr :midi_transport, :atom, default: :stopped
  attr :pipelines, :map, default: %{}

  def app_header(assigns) do
    ~H"""
    <header class="sticky top-0 z-50 bg-gray-900 border-b border-gray-800">
      <div class="flex items-center justify-between px-6 py-3">
        <div class="flex items-center gap-6">
          <a
            href="/"
            class="text-xl font-bold text-purple-400 hover:text-purple-300 transition-colors"
          >
            Sound Forge Alchemy
          </a>
          <span class="hidden sm:inline text-xs text-gray-600">v4.1.0</span>
          <nav class="hidden md:flex items-center gap-1" aria-label="Main navigation">
            <button
              phx-click="nav_tab"
              phx-value-tab="library"
              class={tab_class(@nav_tab == :library)}
            >
              <span class="hero-musical-note w-4 h-4"></span> Library
            </button>
            <button
              phx-click="nav_tab"
              phx-value-tab="browse"
              class={tab_class(@nav_tab == :browse)}
            >
              <span class="hero-magnifying-glass w-4 h-4"></span> Browse
            </button>
            <button
              phx-click="nav_tab"
              phx-value-tab="daw"
              class={tab_class(@nav_tab == :daw)}
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 7h18M3 12h18M3 17h18M6 7v10M10 7v10M14 7v10M18 7v10" />
              </svg>
              DAW
            </button>
            <button
              phx-click="nav_tab"
              phx-value-tab="dj"
              class={tab_class(@nav_tab == :dj)}
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4z" />
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z" />
              </svg>
              DJ
            </button>
            <a
              :if={@current_scope && @current_scope.admin?}
              href="/admin"
              class={[
                "flex items-center gap-1.5 px-3 py-2 text-sm font-medium transition-colors",
                "text-amber-400 border-b-2 border-transparent hover:text-amber-300 hover:border-amber-600"
              ]}
            >
              <span class="hero-shield-check w-4 h-4"></span> Admin
            </a>
          </nav>
        </div>
        <div class="flex items-center gap-3">
          <!-- MIDI Status Indicator with Dropdown -->
          <div class="flex items-center gap-2 text-sm">
            <div class="dropdown dropdown-end">
              <label
                tabindex="0"
                role="button"
                class={[
                  "flex items-center gap-1.5 px-2 py-1 rounded-md text-xs font-medium cursor-pointer transition-colors",
                  if(length(@midi_devices) > 0,
                    do: "bg-green-900/40 text-green-400 border border-green-800/50 hover:bg-green-900/60",
                    else: "bg-gray-800/50 text-gray-500 border border-gray-700/50 hover:bg-gray-800/80 hover:text-gray-400"
                  )
                ]}
                title={midi_tooltip_text(@midi_devices)}
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 9l10.5-3m0 6.553v3.75a2.25 2.25 0 01-1.632 2.163l-1.32.377a1.803 1.803 0 11-.99-3.467l2.31-.66a2.25 2.25 0 001.632-2.163zm0 0V2.25L9 5.25v10.303m0 0v3.75a2.25 2.25 0 01-1.632 2.163l-1.32.377a1.803 1.803 0 01-.99-3.467l2.31-.66A2.25 2.25 0 009 15.553z" />
                </svg>
                <span>MIDI</span>
                <span :if={length(@midi_devices) > 0} class="inline-flex items-center justify-center w-4 h-4 text-[10px] font-bold bg-green-500 text-black rounded-full">
                  {length(@midi_devices)}
                </span>
              </label>
              <div
                tabindex="0"
                class="dropdown-content z-[60] shadow-xl bg-gray-800 border border-gray-700 rounded-lg w-72 mt-2"
              >
                <!-- Dropdown Header -->
                <div class="flex items-center justify-between px-4 py-3 border-b border-gray-700">
                  <h3 class="text-sm font-semibold text-white">MIDI Status</h3>
                  <span class={[
                    "text-[10px] font-medium px-1.5 py-0.5 rounded",
                    if(length(@midi_devices) > 0,
                      do: "bg-green-900/50 text-green-400",
                      else: "bg-gray-700 text-gray-500"
                    )
                  ]}>
                    {if length(@midi_devices) > 0, do: "Connected", else: "No devices"}
                  </span>
                </div>
                <!-- Device List -->
                <div class="px-4 py-3 space-y-2">
                  <div :if={length(@midi_devices) == 0} class="text-center py-2">
                    <p class="text-xs text-gray-500">No MIDI devices connected.</p>
                    <p class="text-[11px] text-gray-600 mt-1">
                      Connect a MIDI controller to enable hardware control.
                    </p>
                  </div>
                  <div :if={length(@midi_devices) > 0}>
                    <p class="text-[10px] text-gray-500 uppercase tracking-wide font-medium mb-1.5">
                      Devices ({length(@midi_devices)})
                    </p>
                    <div class="space-y-1.5">
                      <div
                        :for={device <- @midi_devices}
                        class="flex items-center gap-2.5 px-2.5 py-1.5 bg-gray-900/60 rounded-md"
                      >
                        <div class={[
                          "w-2 h-2 rounded-full shrink-0",
                          if(device.status == :connected, do: "bg-green-500", else: "bg-red-500")
                        ]}></div>
                        <div class="min-w-0 flex-1">
                          <p class="text-xs text-gray-300 truncate">{device.name}</p>
                          <p class="text-[10px] text-gray-600">{device.direction} / {device.type}</p>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
                <!-- Transport & BPM -->
                <div class="px-4 py-2.5 border-t border-gray-700/50 flex items-center gap-3">
                  <div class="flex items-center gap-1.5">
                    <div class={[
                      "w-2 h-2 rounded-full",
                      if(@midi_transport == :playing, do: "bg-green-500 animate-pulse", else: "bg-gray-600")
                    ]}></div>
                    <span class="text-[11px] text-gray-400">
                      {if @midi_transport == :playing, do: "Playing", else: "Stopped"}
                    </span>
                  </div>
                  <span
                    :if={@midi_bpm}
                    class="text-[11px] font-mono text-purple-300"
                  >
                    {Float.round(@midi_bpm * 1.0, 1)} BPM
                  </span>
                </div>
                <!-- Footer Link -->
                <div class="border-t border-gray-700 px-4 py-2.5">
                  <a
                    href="/settings"
                    class="block w-full text-center text-xs text-purple-400 hover:text-purple-300 transition-colors font-medium"
                  >
                    MIDI Settings
                  </a>
                </div>
              </div>
            </div>
            <span
              :if={@midi_bpm}
              class="px-2 py-1 rounded-md text-xs font-mono bg-purple-900/40 text-purple-300 border border-purple-800/50"
            >
              {Float.round(@midi_bpm * 1.0, 1)} BPM
            </span>
          </div>
          <.live_component
            module={SoundForgeWeb.Live.Components.PipelineTracker}
            id="pipeline-tracker"
            pipelines={@pipelines}
          />
          <.live_component
            module={SoundForgeWeb.Live.Components.NotificationBell}
            id="notification-bell"
            user_id={@current_user_id}
            active_pipelines={extract_active_pipelines(@pipelines)}
          />
          <%= if @current_scope do %>
            <div class="dropdown dropdown-end">
              <label
                tabindex="0"
                role="button"
                class="btn btn-ghost btn-sm flex items-center gap-2 text-sm text-gray-400 hover:text-white transition-colors"
              >
                <span class="hero-user-circle w-5 h-5"></span>
                <span class="hidden sm:inline truncate max-w-[120px]">
                  {@current_scope.user.email}
                </span>
              </label>
              <ul
                tabindex="0"
                class="dropdown-content z-[60] menu p-2 shadow-lg bg-gray-800 border border-gray-700 rounded-lg w-48 mt-2"
              >
                <li><a href="/settings" class="text-gray-300 hover:text-white">Settings</a></li>
                <li :if={@current_scope && @current_scope.admin?}>
                  <a href="/admin" class="text-amber-400 hover:text-amber-300">Admin Dashboard</a>
                </li>
                <li>
                  <a href="/users/log-out" data-method="delete" class="text-gray-300 hover:text-white">
                    Log out
                  </a>
                </li>
              </ul>
            </div>
          <% end %>
        </div>
      </div>
      <!-- Sub-navigation row (responsive quick nav) -->
      <div
        class="md:hidden flex items-center gap-1 px-6 pb-2 overflow-x-auto"
        aria-label="Quick navigation"
      >
        <%= cond do %>
          <% @nav_tab == :library -> %>
            <button
              phx-click="nav_all_tracks"
              class={sub_nav_class(@nav_context == :all_tracks)}
            >
              All Tracks
            </button>
            <button
              phx-click="nav_recent"
              class={sub_nav_class(@nav_context == :recent)}
            >
              Recently Added
            </button>
          <% @nav_tab == :browse -> %>
            <button
              phx-click="nav_artists"
              class={sub_nav_class(@nav_context == :artist)}
            >
              Artists
            </button>
            <button
              phx-click="nav_albums"
              class={sub_nav_class(@nav_context == :album)}
            >
              Albums
            </button>
          <% @nav_tab in [:dj, :daw] -> %>
            <%!-- No sub-nav for DJ/DAW modes --%>
          <% true -> %>
            <%!-- Fallback: empty --%>
        <% end %>
      </div>
    </header>
    """
  end

  defp tab_class(true) do
    "flex items-center gap-1.5 px-3 py-2 text-sm font-medium text-purple-400 border-b-2 border-purple-500 transition-colors"
  end

  defp tab_class(false) do
    "flex items-center gap-1.5 px-3 py-2 text-sm font-medium text-gray-400 border-b-2 border-transparent hover:text-white hover:border-gray-600 transition-colors"
  end

  defp sub_nav_class(true) do
    "px-3 py-1 text-xs font-medium text-purple-400 bg-purple-500/10 rounded-full whitespace-nowrap transition-colors"
  end

  defp sub_nav_class(false) do
    "px-3 py-1 text-xs font-medium text-gray-500 hover:text-white hover:bg-gray-800 rounded-full whitespace-nowrap transition-colors"
  end

  defp midi_tooltip_text(devices) when is_list(devices) and length(devices) > 0 do
    count = length(devices)
    suffix = if count == 1, do: "device connected", else: "devices connected"
    names = Enum.map_join(devices, ", ", & &1.name)
    "#{count} MIDI #{suffix}: #{names}"
  end

  defp midi_tooltip_text(_devices) do
    "No MIDI devices connected. Connect a MIDI controller to enable hardware control."
  end

  @active_statuses [:downloading, :processing, :analyzing, :queued]

  # Extracts active pipeline stages from the pipelines map into a flat list of
  # tuples: {track_id, track_title, stage, status, progress}
  # Used to pass transient in-flight actions to the NotificationBell component.
  defp extract_active_pipelines(pipelines) when is_map(pipelines) do
    pipelines
    |> Enum.flat_map(fn {track_id, pipeline} ->
      pipeline
      |> Enum.filter(fn
        {stage, %{status: status}} when is_atom(stage) -> status in @active_statuses
        _ -> false
      end)
      |> Enum.map(fn {stage, %{status: status, progress: progress}} ->
        track_title = pipeline_track_label(track_id)
        {track_id, track_title, stage, status, progress}
      end)
    end)
  end

  defp extract_active_pipelines(_), do: []

  defp pipeline_track_label(track_id) when is_binary(track_id) do
    case SoundForge.Music.get_track(track_id) do
      {:ok, %{title: title}} when is_binary(title) and title != "" -> title
      _ -> "Track #{String.slice(track_id, 0, 8)}..."
    end
  rescue
    _ -> "Track"
  end

  defp pipeline_track_label(_), do: "Track"
end
