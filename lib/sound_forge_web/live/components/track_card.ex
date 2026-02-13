defmodule SoundForgeWeb.Components.TrackCard do
  use Phoenix.Component

  attr :track, :map, required: true
  attr :class, :string, default: ""

  def track_card(assigns) do
    ~H"""
    <div class={[
      "bg-gray-800 rounded-lg p-4 hover:bg-gray-750 transition-colors cursor-pointer border border-gray-700",
      @class
    ]}>
      <div class="aspect-square bg-gray-700 rounded-md mb-3 overflow-hidden">
        <img
          :if={@track.album_art_url}
          src={@track.album_art_url}
          class="w-full h-full object-cover"
          alt={@track.title}
        />
      </div>
      <h3 class="font-medium text-white truncate">{@track.title}</h3>
      <p class="text-sm text-gray-400 truncate">{@track.artist}</p>
      <p class="text-xs text-gray-500">{@track.album}</p>
    </div>
    """
  end
end
