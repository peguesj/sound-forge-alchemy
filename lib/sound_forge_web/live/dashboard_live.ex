defmodule SoundForgeWeb.DashboardLive do
  use SoundForgeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "tracks")
    end

    socket =
      socket
      |> assign(:page_title, "Sound Forge Alchemy")
      |> assign(:search_query, "")
      |> assign(:spotify_url, "")
      |> assign(:active_jobs, %{})
      |> assign(:track_count, 0)
      |> stream(:tracks, list_tracks())

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    tracks = search_tracks(query)

    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:track_count, length(tracks))
      |> stream(:tracks, tracks, reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("fetch_spotify", %{"url" => url}, socket) do
    case fetch_spotify_metadata(url) do
      {:ok, metadata} ->
        {:noreply,
         socket
         |> put_flash(:info, "Fetched: #{metadata["name"]}")
         |> assign(:spotify_url, "")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{reason}")}
    end
  end

  @impl true
  def handle_info({:track_added, track}, socket) do
    {:noreply,
     socket
     |> stream_insert(:tracks, track, at: 0)
     |> update(:track_count, &(&1 + 1))}
  end

  @impl true
  def handle_info({:job_progress, payload}, socket) do
    jobs = Map.put(socket.assigns.active_jobs, payload.job_id, payload)
    {:noreply, assign(socket, :active_jobs, jobs)}
  end

  defp list_tracks do
    try do
      SoundForge.Music.list_tracks()
    rescue
      _ -> []
    end
  end

  defp search_tracks(query) when byte_size(query) > 0 do
    try do
      SoundForge.Music.search_tracks(query)
    rescue
      _ -> list_tracks()
    end
  end

  defp search_tracks(_), do: list_tracks()

  defp fetch_spotify_metadata(url) do
    try do
      SoundForge.Spotify.fetch_metadata(url)
    rescue
      _ -> {:error, "Spotify module not available"}
    end
  end
end
