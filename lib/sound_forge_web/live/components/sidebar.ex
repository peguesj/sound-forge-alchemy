defmodule SoundForgeWeb.Live.Components.Sidebar do
  @moduledoc """
  Sidebar navigation component for the app shell layout.
  Renders library sections (All Tracks, Recently Added), playlists, and browse categories.
  """
  use Phoenix.Component

  attr :nav_tab, :atom, default: :library
  attr :nav_context, :atom, default: :all_tracks
  attr :browse_filter, :any, default: nil
  attr :playlists, :list, default: []
  attr :artists, :list, default: []
  attr :albums, :list, default: []
  attr :track_count, :integer, default: 0

  def sidebar(assigns) do
    ~H"""
    <aside :if={@nav_tab not in [:dj, :daw, :pads]} class="w-56 shrink-0 bg-gray-900 border-r border-gray-800 overflow-y-auto hidden md:block sidebar-scroll">
      <nav class="py-4 space-y-6" aria-label="Library navigation">
        <!-- Library section -->
        <div class="px-4">
          <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Library</h3>
          <ul class="space-y-0.5">
            <li>
              <button
                phx-click="nav_all_tracks"
                class={sidebar_item_class(@nav_context == :all_tracks)}
              >
                <span class="hero-musical-note w-4 h-4 shrink-0"></span>
                <span class="truncate">All Tracks</span>
                <span class="ml-auto text-xs text-gray-600 tabular-nums">{@track_count}</span>
              </button>
            </li>
            <li>
              <button
                phx-click="nav_recent"
                class={sidebar_item_class(@nav_context == :recent)}
              >
                <span class="hero-clock w-4 h-4 shrink-0"></span>
                <span class="truncate">Recently Added</span>
              </button>
            </li>
          </ul>
        </div>
        
    <!-- Playlists section -->
        <div class="px-4">
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Playlists</h3>
            <button
              phx-click="new_playlist"
              class="text-gray-500 hover:text-purple-400 transition-colors"
              aria-label="Create new playlist"
            >
              <span class="hero-plus w-4 h-4"></span>
            </button>
          </div>
          <ul class="space-y-0.5">
            <li :if={@playlists == []} class="px-3 py-1.5 text-xs text-gray-600 italic">
              No playlists yet
            </li>
            <li :for={playlist <- @playlists}>
              <button
                phx-click="nav_playlist"
                phx-value-id={playlist.id}
                class={
                  sidebar_item_class(
                    @nav_context == :playlist && @browse_filter && @browse_filter.id == playlist.id
                  )
                }
              >
                <span class="hero-queue-list w-4 h-4 shrink-0"></span>
                <span class="truncate">{playlist.name}</span>
              </button>
            </li>
          </ul>
        </div>
        
    <!-- Browse section -->
        <div class="px-4">
          <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Browse</h3>
          <ul class="space-y-0.5">
            <li>
              <button
                phx-click="nav_artists"
                class={sidebar_item_class(@nav_context == :artist && is_nil(@browse_filter))}
              >
                <span class="hero-user-group w-4 h-4 shrink-0"></span>
                <span class="truncate">Artists</span>
                <span class="ml-auto text-xs text-gray-600 tabular-nums">{length(@artists)}</span>
              </button>
            </li>
            <li>
              <button
                phx-click="nav_albums"
                class={sidebar_item_class(@nav_context == :album && is_nil(@browse_filter))}
              >
                <span class="hero-square-3-stack-3d w-4 h-4 shrink-0"></span>
                <span class="truncate">Albums</span>
                <span class="ml-auto text-xs text-gray-600 tabular-nums">{length(@albums)}</span>
              </button>
            </li>
          </ul>
        </div>

    <!-- Studio section -->
        <div class="px-4">
          <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Studio</h3>
          <ul class="space-y-0.5">
            <li>
              <button
                phx-click="nav_tab"
                phx-value-tab="daw"
                class={sidebar_item_class(@nav_tab == :daw)}
              >
                <svg class="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M3 7h18M3 12h18M3 17h18M6 7v10M10 7v10M14 7v10M18 7v10" />
                </svg>
                <span class="truncate">DAW</span>
              </button>
            </li>
            <li>
              <button
                phx-click="nav_tab"
                phx-value-tab="dj"
                class={sidebar_item_class(@nav_tab == :dj)}
              >
                <svg class="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4z" />
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z" />
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 12h.01" />
                </svg>
                <span class="truncate">DJ</span>
              </button>
            </li>
            <li>
              <button
                phx-click="nav_tab"
                phx-value-tab="pads"
                class={sidebar_item_class(@nav_tab == :pads)}
              >
                <svg class="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M4 5a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 15a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H5a1 1 0 01-1-1v-4zM14 15a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z" />
                </svg>
                <span class="truncate">Pads</span>
              </button>
            </li>
          </ul>
        </div>
      </nav>
    </aside>
    """
  end

  defp sidebar_item_class(true) do
    "w-full flex items-center gap-2 px-3 py-1.5 text-sm text-purple-400 bg-purple-500/10 rounded-md transition-colors"
  end

  defp sidebar_item_class(false) do
    "w-full flex items-center gap-2 px-3 py-1.5 text-sm text-gray-400 hover:text-white hover:bg-gray-800 rounded-md transition-colors"
  end
end
