defmodule SoundForgeWeb.DashboardLive do
  use SoundForgeWeb, :live_view

  alias SoundForge.Music

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "tracks")
    end

    scope = socket.assigns[:current_scope]

    socket =
      socket
      |> assign(:page_title, "Sound Forge Alchemy")
      |> assign(:search_query, "")
      |> assign(:spotify_url, "")
      |> assign(:active_jobs, %{})
      |> assign(:track_count, 0)
      |> assign(:track, nil)
      |> assign(:stems, [])
      |> assign(:analysis, nil)
      |> stream(:tracks, list_tracks(scope))

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    track = Music.get_track_with_details!(id)
    analysis = List.first(track.analysis_results)

    if connected?(socket) do
      Enum.each(track.stems, fn stem ->
        Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{stem.processing_job_id}")
      end)
    end

    {:noreply,
     socket
     |> assign(:page_title, track.title)
     |> assign(:live_action, :show)
     |> assign(:track, track)
     |> assign(:stems, track.stems)
     |> assign(:analysis, analysis)}
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket
       |> put_flash(:error, "Track not found")
       |> push_navigate(to: ~p"/")}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :live_action, :index)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    scope = socket.assigns[:current_scope]
    tracks = search_tracks(query, scope)

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

  defp list_tracks(scope) when is_map(scope) and not is_nil(scope) do
    try do
      Music.list_tracks(scope)
    rescue
      _ -> []
    end
  end

  defp list_tracks(_scope) do
    try do
      Music.list_tracks()
    rescue
      _ -> []
    end
  end

  defp search_tracks(query, scope) when byte_size(query) > 0 and is_map(scope) and not is_nil(scope) do
    try do
      Music.search_tracks(query, scope)
    rescue
      _ -> list_tracks(scope)
    end
  end

  defp search_tracks(query, _scope) when byte_size(query) > 0 do
    try do
      Music.search_tracks(query)
    rescue
      _ -> list_tracks(nil)
    end
  end

  defp search_tracks(_, scope), do: list_tracks(scope)

  defp fetch_spotify_metadata(url) do
    try do
      SoundForge.Spotify.fetch_metadata(url)
    rescue
      _ -> {:error, "Spotify module not available"}
    end
  end
end
