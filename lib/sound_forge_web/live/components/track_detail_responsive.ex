defmodule SoundForgeWeb.Live.Components.TrackDetailResponsive do
  @moduledoc "Responsive wrapper for track detail view with tab navigation."
  use Phoenix.Component

  attr :active_tab, :atom, default: :stems
  attr :track, :map, required: true
  slot :stems_content
  slot :analysis_content
  slot :details_content

  def track_detail_tabs(assigns) do
    ~H"""
    <div id="track-detail-tabs" phx-hook="SwipeHook" class="w-full">
      <!-- Tab bar (mobile: scrollable, desktop: inline) -->
      <div class="flex border-b border-gray-800 overflow-x-auto md:overflow-visible">
        <button
          :for={tab <- [:stems, :analysis, :details]}
          phx-click="switch_detail_tab"
          phx-value-tab={tab}
          class={"flex-shrink-0 px-4 py-3 min-w-[44px] min-h-[44px] text-sm font-medium border-b-2 transition-colors " <>
            if(@active_tab == tab,
              do: "border-purple-500 text-purple-400",
              else: "border-transparent text-gray-500 hover:text-gray-300")}
        >
          {tab_label(tab)}
        </button>
      </div>

      <!-- Tab content -->
      <div class="mt-4">
        <div :if={@active_tab == :stems}>{render_slot(@stems_content)}</div>
        <div :if={@active_tab == :analysis}>{render_slot(@analysis_content)}</div>
        <div :if={@active_tab == :details}>{render_slot(@details_content)}</div>
      </div>
    </div>
    """
  end

  @doc "Responsive album art component."
  attr :src, :string, default: nil
  attr :alt, :string, default: "Album art"

  def responsive_album_art(assigns) do
    ~H"""
    <div class="flex-shrink-0">
      <img
        :if={@src}
        src={@src}
        alt={@alt}
        class="w-[120px] h-[120px] md:w-[200px] md:h-[200px] rounded-lg object-cover"
      />
      <div
        :if={!@src}
        class="w-[120px] h-[120px] md:w-[200px] md:h-[200px] rounded-lg bg-gray-800 flex items-center justify-center"
      >
        <svg class="w-12 h-12 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2z" />
        </svg>
      </div>
    </div>
    """
  end

  @doc "Accordion component for stem list on mobile."
  attr :items, :list, default: []
  attr :expanded, :string, default: nil

  def stem_accordion(assigns) do
    ~H"""
    <div class="md:hidden space-y-1">
      <div :for={item <- @items} class="border border-gray-800 rounded-lg overflow-hidden">
        <button
          phx-click="toggle_accordion"
          phx-value-id={item.id}
          class="w-full flex items-center justify-between px-4 py-3 min-h-[44px] text-left text-sm text-gray-300 bg-gray-900 hover:bg-gray-800"
        >
          <span>{item.name || item.type}</span>
          <svg class={"w-4 h-4 transition-transform " <> if(@expanded == item.id, do: "rotate-180", else: "")} fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
        <div :if={@expanded == item.id} class="px-4 py-3 bg-gray-950 text-sm text-gray-400">
          <!-- Stem details rendered here -->
          <p>Type: {item.type}</p>
          <p :if={item[:duration]}>Duration: {item.duration}s</p>
        </div>
      </div>
    </div>
    <!-- Desktop: always visible list -->
    <div class="hidden md:block space-y-2">
      <div :for={item <- @items} class="px-4 py-2 bg-gray-900 rounded-lg text-sm text-gray-300">
        <span class="font-medium">{item.name || item.type}</span>
      </div>
    </div>
    """
  end

  defp tab_label(:stems), do: "Stems"
  defp tab_label(:analysis), do: "Analysis"
  defp tab_label(:details), do: "Details"
end
