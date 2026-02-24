defmodule SoundForgeWeb.Live.Components.MobileNav do
  @moduledoc "Bottom navigation bar for mobile viewports."
  use Phoenix.Component

  attr :active_tab, :atom, default: :library
  attr :midi_device_count, :integer, default: 0

  def mobile_nav(assigns) do
    ~H"""
    <nav class="md:hidden fixed bottom-0 left-0 right-0 z-50 bg-gray-900/95 backdrop-blur border-t border-gray-800 safe-area-bottom">
      <div class="flex items-center justify-around h-14">
        <button
          phx-click="nav_tab"
          phx-value-tab="library"
          class={"flex flex-col items-center justify-center w-full h-full min-w-[44px] min-h-[44px] " <> if(@active_tab == :library, do: "text-purple-400", else: "text-gray-500")}
        >
          <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3" />
          </svg>
          <span class="text-[10px] mt-0.5">Library</span>
        </button>

        <button
          phx-click="nav_tab"
          phx-value-tab="player"
          class={"flex flex-col items-center justify-center w-full h-full min-w-[44px] min-h-[44px] " <> if(@active_tab == :player, do: "text-purple-400", else: "text-gray-500")}
        >
          <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span class="text-[10px] mt-0.5">Player</span>
        </button>

        <button
          phx-click="nav_tab"
          phx-value-tab="daw"
          class={"flex flex-col items-center justify-center w-full h-full min-w-[44px] min-h-[44px] " <> if(@active_tab == :daw, do: "text-purple-400", else: "text-gray-500")}
        >
          <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3 7h18M3 12h18M3 17h18M6 7v10M10 7v10M14 7v10M18 7v10" />
          </svg>
          <span class="text-[10px] mt-0.5">DAW</span>
        </button>

        <button
          phx-click="nav_tab"
          phx-value-tab="dj"
          class={"flex flex-col items-center justify-center w-full h-full min-w-[44px] min-h-[44px] " <> if(@active_tab == :dj, do: "text-purple-400", else: "text-gray-500")}
        >
          <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4z" />
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z" />
          </svg>
          <span class="text-[10px] mt-0.5">DJ</span>
        </button>

        <button
          phx-click="nav_tab"
          phx-value-tab="settings"
          class={"flex flex-col items-center justify-center w-full h-full min-w-[44px] min-h-[44px] " <> if(@active_tab == :settings, do: "text-purple-400", else: "text-gray-500")}
        >
          <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
            <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          <span class="text-[10px] mt-0.5">Settings</span>
        </button>
      </div>
    </nav>
    """
  end
end
