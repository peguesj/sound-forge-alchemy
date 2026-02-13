defmodule SoundForgeWeb.Components.SpotifyInput do
  use Phoenix.Component

  attr :value, :string, default: ""
  attr :class, :string, default: ""

  def spotify_input(assigns) do
    ~H"""
    <div class={["px-6 py-4 bg-gray-900/50", @class]}>
      <form phx-submit="fetch_spotify" class="flex gap-3">
        <input
          type="text"
          name="url"
          value={@value}
          placeholder="Paste a Spotify URL (track, album, or playlist)..."
          class="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-4 py-2 text-white placeholder-gray-500 focus:border-purple-500 focus:ring-1 focus:ring-purple-500"
        />
        <button
          type="submit"
          class="bg-purple-600 hover:bg-purple-700 px-6 py-2 rounded-lg font-medium transition-colors"
        >
          Fetch
        </button>
      </form>
    </div>
    """
  end
end
