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
          <span class="hidden sm:inline text-xs text-gray-600">v3.0.0</span>
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
          </nav>
        </div>
        <div class="flex items-center gap-3">
          <.live_component
            module={SoundForgeWeb.Live.Components.NotificationBell}
            id="notification-bell"
            user_id={@current_user_id}
          />
          <%= if @current_scope do %>
            <div class="dropdown dropdown-end">
              <button
                tabindex="0"
                class="flex items-center gap-2 text-sm text-gray-400 hover:text-white transition-colors"
              >
                <span class="hero-user-circle w-5 h-5"></span>
                <span class="hidden sm:inline truncate max-w-[120px]">
                  {@current_scope.user.email}
                </span>
              </button>
              <ul
                tabindex="0"
                class="dropdown-content z-[1] menu p-2 shadow-lg bg-gray-800 border border-gray-700 rounded-lg w-48 mt-2"
              >
                <li><a href="/settings" class="text-gray-300 hover:text-white">Settings</a></li>
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
        <%= if @nav_tab == :library do %>
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
        <% else %>
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
end
