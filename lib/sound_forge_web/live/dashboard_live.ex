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
      |> assign(:pipelines, %{})
      |> assign(:track_count, 0)
      |> assign(:track, nil)
      |> assign(:stems, [])
      |> assign(:analysis, nil)
      |> assign(:sort_by, :newest)
      |> stream(:tracks, list_tracks(scope))

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    track = Music.get_track_with_details!(id)
    analysis = List.first(track.analysis_results)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")

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
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    sort_atom = String.to_existing_atom(sort_by)
    scope = socket.assigns[:current_scope]
    tracks = list_tracks(scope, sort_by: sort_atom)

    {:noreply,
     socket
     |> assign(:sort_by, sort_atom)
     |> stream(:tracks, tracks, reset: true)}
  end

  @impl true
  def handle_event("fetch_spotify", %{"url" => url}, socket) do
    scope = socket.assigns[:current_scope]

    case fetch_spotify_metadata(url) do
      {:ok, metadata} ->
        tracks_data = extract_track_items(metadata)

        socket =
          Enum.reduce(tracks_data, assign(socket, :spotify_url, ""), fn track_meta, acc ->
            case start_single_pipeline(track_meta, url, scope) do
              {:ok, track, pipeline} ->
                if connected?(acc) do
                  Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")
                end

                pipelines = Map.put(acc.assigns.pipelines, track.id, pipeline)

                acc
                |> assign(:pipelines, pipelines)
                |> stream_insert(:tracks, track, at: 0)
                |> update(:track_count, &(&1 + 1))

              {:error, _} ->
                acc
            end
          end)

        msg =
          if length(tracks_data) > 1,
            do: "Started processing #{length(tracks_data)} tracks",
            else: "Started processing: #{List.first(tracks_data)["name"] || "track"}"

        {:noreply, put_flash(socket, :info, msg)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{reason}")}
    end
  end

  @impl true
  def handle_event("delete_track", %{"id" => id}, socket) do
    case Music.get_track(id) do
      {:ok, track} when not is_nil(track) ->
        case Music.delete_track_with_files(track) do
          {:ok, _} ->
            pipelines = Map.delete(socket.assigns.pipelines, id)

            {:noreply,
             socket
             |> stream_delete_by_dom_id(:tracks, "tracks-#{id}")
             |> assign(:pipelines, pipelines)
             |> update(:track_count, fn c -> max(c - 1, 0) end)
             |> put_flash(:info, "Track deleted")
             |> then(fn s ->
               if socket.assigns.live_action == :show do
                 push_navigate(s, to: ~p"/")
               else
                 s
               end
             end)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete track")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Track not found")}
    end
  end

  @impl true
  def handle_event("dismiss_pipeline", %{"track-id" => track_id}, socket) do
    pipelines = Map.delete(socket.assigns.pipelines, track_id)
    {:noreply, assign(socket, :pipelines, pipelines)}
  end

  @impl true
  def handle_event("retry_pipeline", %{"track-id" => track_id, "stage" => stage}, socket) do
    case retry_pipeline_stage(track_id, String.to_existing_atom(stage)) do
      {:ok, _} ->
        # Reset the failed stage to queued
        pipelines = socket.assigns.pipelines
        pipeline = Map.get(pipelines, track_id, %{})
        stage_atom = String.to_existing_atom(stage)
        updated_pipeline = Map.put(pipeline, stage_atom, %{status: :queued, progress: 0})
        pipelines = Map.put(pipelines, track_id, updated_pipeline)

        {:noreply,
         socket
         |> assign(:pipelines, pipelines)
         |> put_flash(:info, "Retrying #{stage}...")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Retry failed: #{reason}")}
    end
  end

  # Track-level pipeline progress (from workers)
  @impl true
  def handle_info({:pipeline_progress, %{track_id: track_id, stage: stage} = payload}, socket) do
    pipelines = socket.assigns.pipelines
    pipeline = Map.get(pipelines, track_id, %{})
    updated_pipeline = Map.put(pipeline, stage, %{status: payload.status, progress: payload.progress})
    pipelines = Map.put(pipelines, track_id, updated_pipeline)
    {:noreply, assign(socket, :pipelines, pipelines)}
  end

  # Pipeline complete - reload the track to get fresh data
  @impl true
  def handle_info({:pipeline_complete, %{track_id: track_id}}, socket) do
    # Update the pipeline state to show completion
    pipelines = socket.assigns.pipelines
    pipeline = Map.get(pipelines, track_id, %{})

    updated_pipeline =
      pipeline
      |> Map.put(:download, %{status: :completed, progress: 100})
      |> Map.put(:processing, %{status: :completed, progress: 100})
      |> Map.put(:analysis, %{status: :completed, progress: 100})

    pipelines = Map.put(pipelines, track_id, updated_pipeline)

    # Reload the track in the stream with fresh data
    socket =
      case Music.get_track(track_id) do
        {:ok, track} when not is_nil(track) ->
          stream_insert(socket, :tracks, track)

        _ ->
          socket
      end

    {:noreply,
     socket
     |> assign(:pipelines, pipelines)
     |> put_flash(:info, "Pipeline complete! Track is ready.")}
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

  # -- Template helpers --

  def pipeline_track_title(_streams, _track_id), do: "Track"

  def pipeline_complete?(pipeline) do
    match?(%{status: :completed}, Map.get(pipeline, :analysis))
  end


  def normalize_spectral(value, max_expected) when is_number(value) and max_expected > 0 do
    min(100, Float.round(value / max_expected * 100, 1))
  end

  def normalize_spectral(_, _), do: 0
  # -- Private helpers --

  defp start_single_pipeline(track_meta, original_url, scope) do
    # Check for duplicate by spotify_id
    spotify_id = track_meta["id"]
    spotify_url = get_in(track_meta, ["external_urls", "spotify"]) || original_url

    with :ok <- check_duplicate(spotify_id, scope),
         {:ok, track} <- create_track_from_metadata(track_meta, scope),
         {:ok, download_job} <- Music.create_download_job(%{track_id: track.id, status: :queued}) do
      %{
        "track_id" => track.id,
        "spotify_url" => spotify_url,
        "quality" => "320k",
        "job_id" => download_job.id
      }
      |> SoundForge.Jobs.DownloadWorker.new()
      |> Oban.insert()

      pipeline = %{track_id: track.id, download: %{status: :queued, progress: 0}}
      {:ok, track, pipeline}
    end
  end

  defp extract_track_items(%{"tracks" => %{"items" => items}}) when is_list(items) do
    # Album response - items are track objects directly
    Enum.map(items, fn
      %{"track" => track} when is_map(track) -> track  # Playlist items wrap in "track"
      item -> item
    end)
  end

  defp extract_track_items(%{"tracks" => %{"items" => items}} = meta) when is_map(meta) do
    # Playlist response
    items
    |> Enum.filter(fn item -> is_map(item) end)
    |> Enum.map(fn
      %{"track" => track} when is_map(track) -> track
      item -> item
    end)
  end

  defp extract_track_items(metadata) when is_map(metadata) do
    # Single track - wrap in list
    [metadata]
  end

  defp check_duplicate(nil, _scope), do: :ok

  defp check_duplicate(spotify_id, _scope) do
    case Music.get_track_by_spotify_id(spotify_id) do
      nil -> :ok
      _track -> {:error, :duplicate}
    end
  end

  defp create_track_from_metadata(metadata, scope) do
    user_id =
      case scope do
        %{user: %{id: id}} -> id
        _ -> nil
      end

    attrs = %{
      title: metadata["name"] || metadata["title"] || "Unknown",
      artist: extract_artist(metadata),
      album: get_in(metadata, ["album", "name"]) || metadata["album"],
      album_art_url: extract_album_art(metadata),
      spotify_id: metadata["id"],
      spotify_url: metadata["external_urls"]["spotify"],
      duration: metadata["duration_ms"],
      user_id: user_id
    }

    Music.create_track(attrs)
  end

  defp extract_artist(%{"artists" => [%{"name" => name} | _]}), do: name
  defp extract_artist(%{"artist" => artist}) when is_binary(artist), do: artist
  defp extract_artist(_), do: nil

  defp extract_album_art(%{"album" => %{"images" => [%{"url" => url} | _]}}), do: url
  defp extract_album_art(%{"album_art_url" => url}) when is_binary(url), do: url
  defp extract_album_art(_), do: nil

  defp list_tracks(scope, opts \\ [])

  defp list_tracks(scope, opts) when is_map(scope) and not is_nil(scope) do
    try do
      Music.list_tracks(scope, opts)
    rescue
      _ -> []
    end
  end

  defp list_tracks(_scope, opts) do
    try do
      Music.list_tracks(opts)
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

  defp retry_pipeline_stage(track_id, :download) do
    track = Music.get_track!(track_id)

    with {:ok, job} <- Music.create_download_job(%{track_id: track_id, status: :queued}) do
      %{
        "track_id" => track_id,
        "spotify_url" => track.spotify_url,
        "quality" => "320k",
        "job_id" => job.id
      }
      |> SoundForge.Jobs.DownloadWorker.new()
      |> Oban.insert()
    end
  end

  defp retry_pipeline_stage(track_id, :processing) do
    # Find the downloaded file to re-process
    downloads_dir = Application.get_env(:sound_forge, :downloads_dir, "priv/uploads/downloads")
    file_path = Path.join(downloads_dir, "#{track_id}.mp3")
    model = Application.get_env(:sound_forge, :default_demucs_model, "htdemucs")

    with {:ok, job} <- Music.create_processing_job(%{track_id: track_id, model: model, status: :queued}) do
      %{
        "track_id" => track_id,
        "job_id" => job.id,
        "file_path" => file_path,
        "model" => model
      }
      |> SoundForge.Jobs.ProcessingWorker.new()
      |> Oban.insert()
    end
  end

  defp retry_pipeline_stage(track_id, :analysis) do
    downloads_dir = Application.get_env(:sound_forge, :downloads_dir, "priv/uploads/downloads")
    file_path = Path.join(downloads_dir, "#{track_id}.mp3")

    with {:ok, job} <- Music.create_analysis_job(%{track_id: track_id, status: :queued}) do
      %{
        "track_id" => track_id,
        "job_id" => job.id,
        "file_path" => file_path,
        "features" => ["tempo", "key", "energy", "spectral"]
      }
      |> SoundForge.Jobs.AnalysisWorker.new()
      |> Oban.insert()
    end
  end
end
