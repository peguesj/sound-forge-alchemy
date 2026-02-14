defmodule SoundForgeWeb.Live.Components.SpotifyPlayer do
  @moduledoc """
  LiveComponent for Spotify Web Playback SDK controls.

  Renders a sticky footer bar with album art, track info, play/pause,
  and a progress bar. Communicates with the SpotifyPlayer JS hook for
  SDK playback control and receives state updates via events.

  ## Required assigns from parent

    * `spotify_playback` - map with playback state or nil when idle:
      - `:playing` (boolean)
      - `:track_name` (string | nil)
      - `:artist_name` (string | nil)
      - `:album_art_url` (string | nil)
      - `:position_ms` (integer)
      - `:duration_ms` (integer)
    * `spotify_linked` - whether the user has linked their Spotify account
    * `spotify_premium` - whether the user has Spotify Premium (default true)
  """
  use SoundForgeWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:spotify_premium, fn -> true end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook="SpotifyPlayer">
      <%= if !@spotify_linked do %>
        <.not_linked_bar />
      <% else %>
        <%= if !@spotify_premium do %>
          <.premium_required_bar />
        <% else %>
          <%= if @spotify_playback do %>
            <.playback_bar
              playback={@spotify_playback}
              myself={@myself}
            />
          <% else %>
            <.idle_bar />
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # -- Sub-components --

  attr :playback, :map, required: true
  attr :myself, :any, required: true

  defp playback_bar(assigns) do
    ~H"""
    <div class="fixed bottom-0 left-0 right-0 z-50 bg-gray-900 border-t border-gray-800 px-4 py-2">
      <div class="max-w-screen-xl mx-auto flex items-center gap-4">
        <!-- Album Art -->
        <div class="shrink-0">
          <%= if @playback.album_art_url do %>
            <img
              src={@playback.album_art_url}
              alt="Album art"
              class="w-10 h-10 rounded object-cover"
            />
          <% else %>
            <div class="w-10 h-10 rounded bg-gray-800 flex items-center justify-center">
              <svg class="w-5 h-5 text-gray-600" fill="currentColor" viewBox="0 0 24 24">
                <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z" />
              </svg>
            </div>
          <% end %>
        </div>
        
    <!-- Track Info -->
        <div class="min-w-0 w-40">
          <p class="text-sm text-white truncate font-medium">
            {@playback.track_name || "Unknown Track"}
          </p>
          <p class="text-xs text-gray-400 truncate">
            {@playback.artist_name || "Unknown Artist"}
          </p>
        </div>
        
    <!-- Play/Pause -->
        <button
          phx-click="spotify_toggle_play"
          phx-target={@myself}
          aria-label={if @playback.playing, do: "Pause", else: "Play"}
          class="shrink-0 w-9 h-9 rounded-full bg-purple-600 hover:bg-purple-500 flex items-center justify-center transition-colors"
        >
          <svg
            :if={!@playback.playing}
            class="w-4 h-4 ml-0.5 text-white"
            fill="currentColor"
            viewBox="0 0 24 24"
          >
            <path d="M8 5v14l11-7z" />
          </svg>
          <svg
            :if={@playback.playing}
            class="w-4 h-4 text-white"
            fill="currentColor"
            viewBox="0 0 24 24"
          >
            <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
          </svg>
        </button>
        
    <!-- Progress -->
        <div class="flex-1 flex items-center gap-2">
          <span class="text-xs text-gray-500 font-mono w-10 text-right shrink-0">
            {format_ms(@playback.position_ms)}
          </span>
          <div
            class="flex-1 bg-gray-700 rounded-full h-1.5 cursor-pointer group"
            phx-click="spotify_seek_bar"
            phx-target={@myself}
            phx-value-ratio={progress_ratio(@playback)}
          >
            <div
              class="h-1.5 rounded-full bg-purple-500 transition-all duration-300 group-hover:bg-purple-400"
              style={"width: #{progress_percent(@playback)}%"}
            >
            </div>
          </div>
          <span class="text-xs text-gray-500 font-mono w-10 shrink-0">
            {format_ms(@playback.duration_ms)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp idle_bar(assigns) do
    ~H"""
    <div class="fixed bottom-0 left-0 right-0 z-50 bg-gray-900 border-t border-gray-800 px-4 py-2">
      <div class="max-w-screen-xl mx-auto flex items-center gap-4">
        <div class="w-10 h-10 rounded bg-gray-800 flex items-center justify-center shrink-0">
          <svg class="w-5 h-5 text-gray-600" fill="currentColor" viewBox="0 0 24 24">
            <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z" />
          </svg>
        </div>
        <div class="flex-1 min-w-0">
          <p class="text-sm text-gray-500">No track playing</p>
          <p class="text-xs text-gray-600">Select a track to start playback</p>
        </div>
      </div>
    </div>
    """
  end

  defp not_linked_bar(assigns) do
    ~H"""
    <div class="fixed bottom-0 left-0 right-0 z-50 bg-gray-900 border-t border-gray-800 px-4 py-3">
      <div class="max-w-screen-xl mx-auto flex items-center justify-center gap-2">
        <svg class="w-5 h-5 text-green-500 shrink-0" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 0C5.4 0 0 5.4 0 12s5.4 12 12 12 12-5.4 12-12S18.66 0 12 0zm5.521 17.34c-.24.359-.66.48-1.021.24-2.82-1.74-6.36-2.101-10.561-1.141-.418.122-.779-.179-.899-.539-.12-.421.18-.78.54-.9 4.56-1.021 8.52-.6 11.64 1.32.42.18.479.659.301 1.02zm1.44-3.3c-.301.42-.841.6-1.262.3-3.239-1.98-8.159-2.58-11.939-1.38-.479.12-1.02-.12-1.14-.6-.12-.48.12-1.021.6-1.141C9.6 9.9 15 10.561 18.72 12.84c.361.181.54.78.241 1.2zm.12-3.36C15.24 8.4 8.82 8.16 5.16 9.301c-.6.179-1.2-.181-1.38-.721-.18-.601.18-1.2.72-1.381 4.26-1.26 11.28-1.02 15.721 1.621.539.3.719 1.02.419 1.56-.299.421-1.02.599-1.559.3z" />
        </svg>
        <span class="text-sm text-gray-400">
          Link your Spotify account in
          <a href="/settings" class="text-purple-400 hover:text-purple-300 underline">Settings</a>
          to enable playback.
        </span>
      </div>
    </div>
    """
  end

  defp premium_required_bar(assigns) do
    ~H"""
    <div class="fixed bottom-0 left-0 right-0 z-50 bg-gray-900 border-t border-gray-800 px-4 py-3">
      <div class="max-w-screen-xl mx-auto flex items-center justify-center gap-2">
        <svg class="w-5 h-5 text-yellow-500 shrink-0" fill="currentColor" viewBox="0 0 24 24">
          <path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z" />
        </svg>
        <span class="text-sm text-gray-400">
          Spotify Premium is required for Web Playback.
        </span>
      </div>
    </div>
    """
  end

  # -- Events --

  @impl true
  def handle_event("spotify_toggle_play", _params, socket) do
    playback = socket.assigns.spotify_playback

    if playback && playback.playing do
      send(self(), :spotify_pause)
    else
      send(self(), :spotify_resume)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("spotify_seek_bar", %{"ratio" => ratio_str}, socket) do
    playback = socket.assigns.spotify_playback

    if playback do
      ratio = parse_float(ratio_str)
      position_ms = trunc(ratio * playback.duration_ms)
      send(self(), {:spotify_seek, position_ms})
    end

    {:noreply, socket}
  end

  # -- Helpers --

  defp format_ms(nil), do: "0:00"

  defp format_ms(ms) when is_number(ms) do
    total_seconds = div(trunc(ms), 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  defp format_ms(_), do: "0:00"

  defp progress_ratio(%{position_ms: pos, duration_ms: dur})
       when is_number(pos) and is_number(dur) and dur > 0 do
    Float.round(pos / dur, 4)
  end

  defp progress_ratio(_), do: 0.0

  defp progress_percent(playback) do
    Float.round(progress_ratio(playback) * 100, 1)
  end

  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp parse_float(_), do: 0.0
end
