defmodule SoundForgeWeb.Live.Components.MobileDrawer do
  @moduledoc "Slide-out navigation drawer for mobile, replacing desktop sidebar."
  use Phoenix.Component

  attr :open, :boolean, default: false
  attr :nav_context, :atom, default: :library
  slot :inner_block

  def mobile_drawer(assigns) do
    ~H"""
    <div
      :if={@open}
      id="mobile-drawer-overlay"
      class="md:hidden fixed inset-0 z-40 bg-black/60 backdrop-blur-sm"
      phx-click="close_drawer"
    >
      <div
        id="mobile-drawer"
        class="absolute left-0 top-0 bottom-0 w-72 bg-gray-900 border-r border-gray-800 overflow-y-auto"
        phx-click-away="close_drawer"
      >
        <div class="p-4 border-b border-gray-800">
          <h2 class="text-lg font-semibold text-white">Sound Forge Alchemy</h2>
        </div>
        <div class="p-2">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end
end
