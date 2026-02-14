defmodule SoundForgeWeb.Live.Components.Sidebar do
  @moduledoc """
  Sidebar navigation component for the app shell layout.
  Renders library sections (All Tracks, Recently Added), playlists, and browse categories.
  """
  use Phoenix.Component

  attr :nav_context, :atom, default: :all_tracks
  attr :browse_filter, :any, default: nil
  attr :playlists, :list, default: []
  attr :artists, :list, default: []
  attr :albums, :list, default: []
  attr :track_count, :integer, default: 0

  def sidebar(assigns) do
    ~H"""
    <aside class="w-56 shrink-0 bg-gray-900 border-r border-gray-800 overflow-y-auto hidden lg:block sidebar-scroll">
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
