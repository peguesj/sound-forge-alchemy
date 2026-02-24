defmodule SoundForgeWeb.AudioPlayerLive do
  @moduledoc """
  LiveComponent for audio playback with per-stem volume, solo, and mute controls.
  """
  use SoundForgeWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:playing, false)
     |> assign(:current_time, 0)
     |> assign(:duration, 0)
     |> assign(:master_volume, 80)
     |> assign(:stem_volumes, %{})
     |> assign(:muted_stems, MapSet.new())
     |> assign(:solo_stem, nil)}
  end

  @impl true
  def update(assigns, socket) do
    stems = Map.get(assigns, :stems, [])
    track = Map.get(assigns, :track)

    # Build audio sources for the player
    # Priority: stems (if available) > downloaded file (if exists)
    audio_data = build_audio_data(stems, track)
    require Logger
    Logger.debug("AudioPlayerLive: stems=#{length(stems)}, audio_data=#{length(audio_data)}, urls=#{inspect(Enum.map(audio_data, & &1.url))}")

    # Initialize per-stem volumes if not already set
    stem_volumes =
      if map_size(socket.assigns.stem_volumes) == 0 do
        if stems != [] do
          Map.new(stems, fn stem -> {to_string(stem.stem_type), 100} end)
        else
          %{}
        end
      else
        socket.assigns.stem_volumes
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:audio_data, audio_data)
     |> assign(:stem_volumes, stem_volumes)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"audio-player-#{@id}"}
      phx-hook="AudioPlayer"
      data-stems={Jason.encode!(Map.get(assigns, :audio_data, []))}
      class="bg-gray-800 rounded-lg p-6"
    >
      <!-- Waveform -->
      <div class="relative">
        <div id={"waveform-#{@id}"} class="h-20 mb-4 rounded bg-gray-900"></div>
        <div id={"waveform-loading-#{@id}"} class="absolute inset-0 flex items-center justify-center text-gray-500 text-sm">
          <span :if={@audio_data != []}>Loading waveform...</span>
          <span :if={@audio_data == []}>No audio sources available</span>
        </div>
      </div>
      
    <!-- Transport Controls -->
      <div class="flex items-center gap-4 mb-6">
        <button
          phx-click="toggle_play"
          phx-target={@myself}
          aria-label={if @playing, do: "Pause", else: "Play"}
          class="w-12 h-12 rounded-full bg-purple-600 hover:bg-purple-500 flex items-center justify-center transition-colors"
        >
          <svg
            :if={!@playing}
            class="w-5 h-5 ml-0.5 text-white"
            fill="currentColor"
            viewBox="0 0 24 24"
          >
            <path d="M8 5v14l11-7z" />
          </svg>
          <svg :if={@playing} class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 24 24">
            <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
          </svg>
        </button>

        <span class="text-sm text-gray-400 font-mono min-w-[100px]">
          {format_time(@current_time)} / {format_time(@duration)}
        </span>
        
    <!-- Master Volume -->
        <div class="flex items-center gap-2 ml-auto">
          <svg
            class="w-5 h-5 text-gray-400"
            fill="currentColor"
            viewBox="0 0 24 24"
            aria-hidden="true"
          >
            <path d="M3 9v6h4l5 5V4L7 9H3z" />
          </svg>
          <input
            type="range"
            min="0"
            max="100"
            value={@master_volume}
            phx-change="master_volume"
            phx-target={@myself}
            name="level"
            aria-label="Master volume"
            class="w-24 accent-purple-500"
          />
          <span class="text-xs text-gray-500 w-8">{@master_volume}%</span>
        </div>
      </div>
      
    <!-- Per-Stem Controls -->
      <div class="space-y-3">
        <div
          :for={stem <- @stems}
          class="flex items-center gap-4 bg-gray-900 rounded-lg px-4 py-3"
        >
          <!-- Stem Label -->
          <span class={"text-sm font-medium w-16 " <> stem_text_color(stem.stem_type)}>
            {String.capitalize(to_string(stem.stem_type))}
          </span>
          
    <!-- Solo Button -->
          <button
            phx-click="solo_stem"
            phx-value-stem={stem.stem_type}
            phx-target={@myself}
            aria-label={"Solo #{stem.stem_type}"}
            aria-pressed={to_string(@solo_stem == to_string(stem.stem_type))}
            class={"px-2 py-1 rounded text-xs font-medium transition-colors " <>
              if(@solo_stem == to_string(stem.stem_type),
                do: "bg-yellow-500 text-black",
                else: "bg-gray-700 text-gray-400 hover:bg-gray-600")}
          >
            S
          </button>
          
    <!-- Mute Button -->
          <button
            phx-click="toggle_stem"
            phx-value-stem={stem.stem_type}
            phx-target={@myself}
            aria-label={"Mute #{stem.stem_type}"}
            aria-pressed={to_string(MapSet.member?(@muted_stems, to_string(stem.stem_type)))}
            class={"px-2 py-1 rounded text-xs font-medium transition-colors " <>
              if(MapSet.member?(@muted_stems, to_string(stem.stem_type)),
                do: "bg-red-500/20 text-red-400",
                else: "bg-gray-700 text-gray-400 hover:bg-gray-600")}
          >
            M
          </button>
          
    <!-- Volume Slider -->
          <input
            type="range"
            min="0"
            max="100"
            value={Map.get(@stem_volumes, to_string(stem.stem_type), 100)}
            phx-change="stem_volume"
            phx-value-stem={stem.stem_type}
            phx-target={@myself}
            name="level"
            aria-label={"#{String.capitalize(to_string(stem.stem_type))} volume"}
            class={"flex-1 " <> stem_accent_color(stem.stem_type)}
          />
          <span class="text-xs text-gray-500 w-8">
            {Map.get(@stem_volumes, to_string(stem.stem_type), 100)}%
          </span>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_play", _params, socket) do
    new_state = !socket.assigns.playing
    {:noreply,
     socket
     |> assign(:playing, new_state)
     |> push_event("toggle_play", %{})}
  end

  @impl true
  def handle_event("master_volume", %{"level" => level}, socket) do
    level_int = String.to_integer(level)
    {:noreply,
     socket
     |> assign(:master_volume, level_int)
     |> push_event("set_volume", %{level: level_int})}
  end

  @impl true
  def handle_event("stem_volume", %{"level" => level, "stem" => stem}, socket) do
    level_int = String.to_integer(level)
    volumes = Map.put(socket.assigns.stem_volumes, stem, level_int)
    {:noreply,
     socket
     |> assign(:stem_volumes, volumes)
     |> push_event("set_stem_volume", %{stem: stem, level: level_int})}
  end

  @impl true
  def handle_event("toggle_stem", %{"stem" => stem}, socket) do
    muted = socket.assigns.muted_stems

    muted =
      if MapSet.member?(muted, stem),
        do: MapSet.delete(muted, stem),
        else: MapSet.put(muted, stem)

    is_muted = MapSet.member?(muted, stem)

    {:noreply,
     socket
     |> assign(:muted_stems, muted)
     |> push_event("mute_stem", %{stem: stem, muted: is_muted})}
  end

  @impl true
  def handle_event("solo_stem", %{"stem" => stem}, socket) do
    solo =
      if socket.assigns.solo_stem == stem,
        do: nil,
        else: stem

    {:noreply,
     socket
     |> assign(:solo_stem, solo)
     |> push_event("solo_stem", %{stem: solo})}
  end

  @impl true
  def handle_event("player_ready", %{"duration" => duration}, socket) do
    {:noreply, assign(socket, :duration, duration)}
  end

  @impl true
  def handle_event("time_update", %{"time" => time}, socket) do
    {:noreply, assign(socket, :current_time, time)}
  end

  defp stem_data(stems) when stems != [] do
    Enum.map(stems, fn stem ->
      relative = make_relative_path(stem.file_path)

      %{
        type: to_string(stem.stem_type),
        url: "/files/#{relative}",
        file_size: stem.file_size
      }
    end)
  end

  defp stem_data([]) do
    # If no stems, return empty array - AudioPlayer hook will handle this gracefully
    []
  end

  defp make_relative_path(nil), do: ""

  defp make_relative_path(path) do
    base = SoundForge.Storage.base_path() |> Path.expand()
    cwd_base = Path.join(File.cwd!(), SoundForge.Storage.base_path()) |> Path.expand()
    demucs_base = Application.get_env(:sound_forge, :demucs_output_dir, "/tmp/demucs") |> Path.expand()
    expanded = Path.expand(path)

    cond do
      String.starts_with?(expanded, cwd_base <> "/") ->
        String.replace_prefix(expanded, cwd_base <> "/", "")

      String.starts_with?(expanded, base <> "/") ->
        String.replace_prefix(expanded, base <> "/", "")

      String.starts_with?(expanded, demucs_base <> "/") ->
        String.replace_prefix(expanded, demucs_base <> "/", "")

      true ->
        path
    end
  end

  defp format_time(seconds) when is_number(seconds) do
    minutes = trunc(seconds / 60)
    secs = trunc(rem(trunc(seconds), 60))

    "#{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(secs), 2, "0")}"
  end

  defp format_time(_), do: "00:00"

  defp stem_text_color(stem_type) do
    case to_string(stem_type) do
      "vocals" -> "text-purple-400"
      "drums" -> "text-blue-400"
      "bass" -> "text-green-400"
      "other" -> "text-amber-400"
      _ -> "text-gray-400"
    end
  end

  defp stem_accent_color(stem_type) do
    case to_string(stem_type) do
      "vocals" -> "accent-purple-500"
      "drums" -> "accent-blue-500"
      "bass" -> "accent-green-500"
      "other" -> "accent-amber-500"
      _ -> "accent-gray-500"
    end
  end

  defp build_audio_data(stems, _track) when stems != [] do
    # If we have stems, use them (existing behavior)
    stem_data(stems)
  end

  defp build_audio_data([], track) when not is_nil(track) do
    # No stems available, check if we have a downloaded file
    case get_completed_download_path(track) do
      {:ok, path} when not is_nil(path) ->
        # Build a single "full_track" audio source
        relative = make_relative_path(path)
        [
          %{
            type: "full_track",
            url: "/files/#{relative}",
            file_size: get_file_size(path)
          }
        ]

      _ ->
        # No download available, return empty
        []
    end
  end

  defp build_audio_data([], nil), do: []

  defp get_completed_download_path(track) do
    # Check if track has preloaded download_jobs
    case Map.get(track, :download_jobs) do
      jobs when is_list(jobs) ->
        # Find the most recent completed download
        completed =
          jobs
          |> Enum.filter(&(&1.status == :completed and not is_nil(&1.output_path)))
          |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
          |> List.first()

        case completed do
          %{output_path: path} -> {:ok, path}
          _ -> {:error, :no_completed_download}
        end

      _ ->
        # download_jobs not preloaded, fetch it
        alias SoundForge.Music
        Music.get_download_path(track.id)
    end
  end

  defp get_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> nil
    end
  end
end
