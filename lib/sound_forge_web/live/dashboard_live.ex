defmodule SoundForgeWeb.DashboardLive do
  @moduledoc """
  Main dashboard LiveView for track management, pipeline control, and audio playback.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Music
  alias SoundForge.Settings

  @impl true
  def mount(_params, session, socket) do
    scope = socket.assigns[:current_scope]
    current_user_id = resolve_user_id(scope, session)

    socket =
      socket
      |> assign_new(:current_scope, fn -> nil end)
      |> assign(:page_title, "Sound Forge Alchemy")
      |> assign(:current_user_id, current_user_id)
      |> assign(:search_query, "")
      |> assign(:spotify_url, "")
      |> assign(:fetching_spotify, false)
      |> assign(:active_jobs, %{})
      |> assign(:pipelines, %{})
      |> assign(:track_count, count_tracks(scope))
      |> assign(:track, nil)
      |> assign(:stems, [])
      |> assign(:analysis, nil)
      |> assign(:sort_by, :newest)
      |> assign(:view_mode, :grid)
      |> assign(:filters, %{status: "all", artist: "all"})
      |> assign(:artists, list_artists(scope))
      |> assign(:selected_ids, MapSet.new())
      |> assign(:select_all, false)
      |> assign(:auto_download, true)
      |> assign(:editing_track, nil)
      |> assign(:spotify_playback, nil)
      |> assign(:spotify_linked, spotify_linked?(current_user_id))
      |> assign(:spotify_premium, true)
      |> assign(:nav_tab, :library)
      |> assign(:nav_context, :all_tracks)
      |> assign(:browse_filter, nil)
      |> assign(:playlists, list_playlists(scope))
      |> assign(:albums, list_albums(scope))
      |> assign(:page, 1)
      |> assign(:per_page, per_page(current_user_id))
      |> allow_upload(:audio,
        accept: ~w(.mp3 .wav .flac .ogg .m4a .aac .wma),
        max_entries: 5,
        max_file_size: Settings.get(current_user_id, :max_upload_size)
      )
      |> stream(:tracks, list_tracks(scope, page: 1, per_page: per_page(current_user_id)))

    socket =
      if connected?(socket) and current_user_id do
        SoundForge.Notifications.subscribe(current_user_id)

        # Send Spotify token once on mount so the SDK player can initialize
        case SoundForge.Spotify.OAuth.get_valid_access_token(current_user_id) do
          {:ok, token} -> push_event(socket, "spotify_token", %{token: token})
          _ -> socket
        end
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    track = Music.get_track_with_details!(id)

    if owns_track?(socket, track) do
      subscribe_to_track(socket, track)
      analysis = List.first(track.analysis_results)

      {:noreply,
       socket
       |> assign(:page_title, track.title)
       |> assign(:live_action, :show)
       |> assign(:track, track)
       |> assign(:stems, track.stems)
       |> assign(:analysis, analysis)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Track not found")
       |> push_navigate(to: ~p"/")}
    end
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

  @valid_view_modes ~w(grid list list_expanded)a

  @impl true
  def handle_event("toggle_view", %{"mode" => mode}, socket) do
    view_mode =
      try do
        atom = String.to_existing_atom(mode)
        if atom in @valid_view_modes, do: atom, else: :grid
      rescue
        ArgumentError -> :grid
      end

    scope = socket.assigns[:current_scope]
    per_page = socket.assigns.per_page
    sort_by = socket.assigns.sort_by
    page = socket.assigns.page
    filters = socket.assigns.filters

    tracks =
      list_tracks(scope, sort_by: sort_by, page: page, per_page: per_page, filters: filters)

    {:noreply,
     socket
     |> assign(:view_mode, view_mode)
     |> stream(:tracks, tracks, reset: true)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = %{
      status: Map.get(params, "status", "all"),
      artist: Map.get(params, "artist", "all")
    }

    reload_tracks(socket, filters: filters, page: 1)
  end

  # -- Multi-Select --

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    if socket.assigns.select_all do
      {:noreply,
       socket
       |> assign(:selected_ids, MapSet.new())
       |> assign(:select_all, false)}
    else
      # Select all track IDs on current page from the stream
      scope = socket.assigns[:current_scope]
      per_page = socket.assigns.per_page
      sort_by = socket.assigns.sort_by
      page = socket.assigns.page

      track_ids =
        list_tracks(scope, sort_by: sort_by, page: page, per_page: per_page)
        |> Enum.map(& &1.id)
        |> MapSet.new()

      {:noreply,
       socket
       |> assign(:selected_ids, track_ids)
       |> assign(:select_all, true)}
    end
  end

  @impl true
  def handle_event("shift_select_range", %{"from_id" => from_id, "to_id" => to_id}, socket) do
    scope = socket.assigns[:current_scope]
    per_page = socket.assigns.per_page
    sort_by = socket.assigns.sort_by
    page = socket.assigns.page

    all_ids =
      list_tracks(scope, sort_by: sort_by, page: page, per_page: per_page)
      |> Enum.map(& &1.id)

    from_idx = Enum.find_index(all_ids, &(&1 == from_id)) || 0
    to_idx = Enum.find_index(all_ids, &(&1 == to_id)) || 0
    {min_idx, max_idx} = {min(from_idx, to_idx), max(from_idx, to_idx)}

    range_ids =
      all_ids
      |> Enum.slice(min_idx..max_idx)
      |> MapSet.new()

    selected = MapSet.union(socket.assigns.selected_ids, range_ids)
    {:noreply, assign(socket, :selected_ids, selected)}
  end

  # -- Batch Actions --

  @impl true
  def handle_event("batch_analyze", _params, socket) do
    selected = socket.assigns.selected_ids
    count = MapSet.size(selected)
    user_id = socket.assigns[:current_user_id]

    Enum.each(selected, fn track_id ->
      with {:ok, track} <- fetch_owned_track(socket, track_id) do
        retry_pipeline_stage(track.id, :analysis, user_id)
        maybe_subscribe(socket, track.id)
      end
    end)

    {:noreply,
     socket
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> put_flash(:info, "Analyzing #{count} tracks...")}
  end

  @impl true
  def handle_event("batch_process", _params, socket) do
    selected = socket.assigns.selected_ids
    count = MapSet.size(selected)
    user_id = socket.assigns[:current_user_id]

    Enum.each(selected, fn track_id ->
      with {:ok, track} <- fetch_owned_track(socket, track_id) do
        retry_pipeline_stage(track.id, :processing, user_id)
        maybe_subscribe(socket, track.id)
      end
    end)

    {:noreply,
     socket
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> put_flash(:info, "Processing #{count} tracks...")}
  end

  @impl true
  def handle_event("batch_delete", _params, socket) do
    selected = socket.assigns.selected_ids
    count = MapSet.size(selected)

    socket = Enum.reduce(selected, socket, &delete_single_track(&2, &1))

    {:noreply,
     socket
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> put_flash(:info, "Deleted #{count} tracks")}
  end

  # -- Download Actions --

  @impl true
  def handle_event("download_track", %{"id" => id}, socket) do
    user_id = socket.assigns[:current_user_id]

    with {:ok, track} <- fetch_owned_track(socket, id),
         true <- is_binary(track.spotify_url) do
      {:ok, download_job} = Music.create_download_job(%{track_id: track.id, status: :queued})

      %{
        "track_id" => track.id,
        "spotify_url" => track.spotify_url,
        "quality" => Settings.get(user_id, :download_quality),
        "job_id" => download_job.id
      }
      |> SoundForge.Jobs.DownloadWorker.new()
      |> Oban.insert()

      maybe_subscribe(socket, track.id)

      pipelines = socket.assigns.pipelines
      pipeline = Map.get(pipelines, track.id, %{})
      updated_pipeline = Map.put(pipeline, :download, %{status: :queued, progress: 0})
      pipelines = Map.put(pipelines, track.id, updated_pipeline)

      {:noreply,
       socket
       |> assign(:pipelines, pipelines)
       |> put_flash(:info, "Download started for #{track.title}")}
    else
      false ->
        {:noreply, put_flash(socket, :error, "Track has no Spotify URL")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Track not found")}
    end
  end

  @impl true
  def handle_event("toggle_auto_download", _params, socket) do
    {:noreply, update(socket, :auto_download, &(!&1))}
  end

  @impl true
  def handle_event("process_track", %{"id" => id}, socket) do
    user_id = socket.assigns[:current_user_id]

    with {:ok, track} <- fetch_owned_track(socket, id),
         {:ok, _} <- retry_pipeline_stage(track.id, :processing, user_id) do
      maybe_subscribe(socket, track.id)

      pipelines = socket.assigns.pipelines
      pipeline = Map.get(pipelines, track.id, %{})
      updated_pipeline = Map.put(pipeline, :processing, %{status: :queued, progress: 0})
      pipelines = Map.put(pipelines, track.id, updated_pipeline)

      {:noreply,
       socket
       |> assign(:pipelines, pipelines)
       |> put_flash(:info, "Processing #{track.title}...")}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Track not found")}

      {:error, :no_completed_download} ->
        {:noreply, put_flash(socket, :error, "Download the track first before processing")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not start processing")}
    end
  end

  @impl true
  def handle_event("analyze_track", %{"id" => id}, socket) do
    user_id = socket.assigns[:current_user_id]

    with {:ok, track} <- fetch_owned_track(socket, id),
         {:ok, _} <- retry_pipeline_stage(track.id, :analysis, user_id) do
      maybe_subscribe(socket, track.id)

      pipelines = socket.assigns.pipelines
      pipeline = Map.get(pipelines, track.id, %{})
      updated_pipeline = Map.put(pipeline, :analysis, %{status: :queued, progress: 0})
      pipelines = Map.put(pipelines, track.id, updated_pipeline)

      {:noreply,
       socket
       |> assign(:pipelines, pipelines)
       |> put_flash(:info, "Analyzing #{track.title}...")}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Track not found")}

      {:error, :no_completed_download} ->
        {:noreply, put_flash(socket, :error, "Download the track first before analyzing")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not start analysis")}
    end
  end

  @impl true
  def handle_event(
        "add_to_playlist",
        %{"track-id" => track_id, "playlist-id" => playlist_id},
        socket
      ) do
    with {:ok, track} <- fetch_owned_track(socket, track_id),
         playlist <- Music.get_playlist!(playlist_id) do
      case Music.add_track_to_playlist(playlist, track) do
        {:ok, _} ->
          {:noreply, put_flash(socket, :info, "Added to playlist")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Track already in playlist")}
      end
    else
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Track not found")}
    end
  end

  @impl true
  def handle_event("batch_download", _params, socket) do
    selected = socket.assigns.selected_ids
    user_id = socket.assigns[:current_user_id]
    count = MapSet.size(selected)

    downloaded =
      Enum.reduce(selected, 0, fn track_id, acc ->
        with {:ok, track} <- fetch_owned_track(socket, track_id),
             true <- is_binary(track.spotify_url),
             # Skip tracks that already have a completed download
             false <- has_completed_download?(track_id) do
          {:ok, download_job} = Music.create_download_job(%{track_id: track.id, status: :queued})

          %{
            "track_id" => track.id,
            "spotify_url" => track.spotify_url,
            "quality" => Settings.get(user_id, :download_quality),
            "job_id" => download_job.id
          }
          |> SoundForge.Jobs.DownloadWorker.new()
          |> Oban.insert()

          maybe_subscribe(socket, track.id)
          acc + 1
        else
          _ -> acc
        end
      end)

    {:noreply,
     socket
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> put_flash(:info, "Downloading #{downloaded} of #{count} selected tracks...")}
  end

  # -- Metadata Editing --

  @impl true
  def handle_event("edit_metadata", %{"id" => id}, socket) do
    case fetch_owned_track(socket, id) do
      {:ok, track} ->
        changeset = Music.change_track(track)
        {:noreply, assign(socket, :editing_track, {track, changeset})}

      _ ->
        {:noreply, put_flash(socket, :error, "Track not found")}
    end
  end

  @impl true
  def handle_event("save_metadata", %{"track" => params}, socket) do
    case socket.assigns.editing_track do
      {track, _changeset} ->
        case Music.update_track(track, params) do
          {:ok, updated_track} ->
            {:noreply,
             socket
             |> stream_insert(:tracks, updated_track)
             |> assign(:editing_track, nil)
             |> put_flash(:info, "Track updated")}

          {:error, changeset} ->
            {:noreply, assign(socket, :editing_track, {track, changeset})}
        end

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_track, nil)}
  end

  # -- Spotify Playback --

  @impl true
  def handle_event("play_spotify", %{"uri" => uri}, socket) do
    user_id = socket.assigns[:current_user_id]

    case SoundForge.Spotify.OAuth.get_valid_access_token(user_id) do
      {:ok, token} ->
        # Push a refreshed token (JS hook will skip re-init if already connected)
        # then push the play event
        {:noreply,
         socket
         |> push_event("spotify_token", %{token: token})
         |> push_event("spotify_play", %{uri: uri})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Spotify not linked or token expired")}
    end
  end

  @impl true
  def handle_event("spotify_player_ready", %{"device_id" => _device_id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("spotify_playback_state", params, socket) do
    playback = %{
      playing: params["playing"] || false,
      track_name: params["track_name"],
      artist_name: params["artist_name"],
      album_art_url: params["album_art_url"],
      position_ms: params["position_ms"] || 0,
      duration_ms: params["duration_ms"] || 0
    }

    {:noreply, assign(socket, :spotify_playback, playback)}
  end

  @impl true
  def handle_event("spotify_error", %{"type" => "account"} = _params, socket) do
    {:noreply, assign(socket, :spotify_premium, false)}
  end

  @impl true
  def handle_event("spotify_error", %{"type" => type, "message" => message}, socket) do
    toast_type = if type in ["initialization", "connection"], do: :warning, else: :error

    send_update(SoundForgeWeb.Live.Components.ToastStack,
      id: "toast-stack",
      toast: %{type: toast_type, title: "Spotify", message: message}
    )

    {:noreply, socket}
  end

  def handle_event("spotify_error", %{"message" => message}, socket) do
    send_update(SoundForgeWeb.Live.Components.ToastStack,
      id: "toast-stack",
      toast: %{type: :error, title: "Spotify", message: message}
    )

    {:noreply, socket}
  end

  @valid_sort_fields ~w(newest oldest title artist duration)a

  @impl true
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    sort_atom =
      try do
        atom = String.to_existing_atom(sort_by)
        if atom in @valid_sort_fields, do: atom, else: :newest
      rescue
        ArgumentError -> :newest
      end

    reload_tracks(socket, sort_by: sort_atom, page: 1)
  end

  # -- Navigation --

  @impl true
  def handle_event("nav_tab", %{"tab" => tab}, socket) do
    nav_tab = String.to_existing_atom(tab)
    {:noreply, assign(socket, :nav_tab, nav_tab)}
  rescue
    ArgumentError -> {:noreply, socket}
  end

  @impl true
  def handle_event("nav_all_tracks", _params, socket) do
    socket =
      socket
      |> assign(:nav_tab, :library)
      |> assign(:nav_context, :all_tracks)
      |> assign(:browse_filter, nil)
      |> assign(:page, 1)
      |> assign(:filters, %{status: "all", artist: "all"})

    reload_tracks(socket, page: 1, filters: %{status: "all", artist: "all"})
  end

  @impl true
  def handle_event("nav_recent", _params, socket) do
    scope = socket.assigns[:current_scope]
    seven_days_ago = DateTime.utc_now() |> DateTime.add(-7, :day)

    tracks =
      list_tracks(scope, sort_by: :newest, page: 1, per_page: socket.assigns.per_page)
      |> Enum.filter(fn track ->
        case track.inserted_at do
          %NaiveDateTime{} = dt ->
            DateTime.from_naive!(dt, "Etc/UTC")
            |> DateTime.compare(seven_days_ago) != :lt

          %DateTime{} = dt ->
            DateTime.compare(dt, seven_days_ago) != :lt

          _ ->
            false
        end
      end)

    {:noreply,
     socket
     |> assign(:nav_tab, :library)
     |> assign(:nav_context, :recent)
     |> assign(:browse_filter, nil)
     |> assign(:page, 1)
     |> assign(:track_count, length(tracks))
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> stream(:tracks, tracks, reset: true)}
  end

  @impl true
  def handle_event("nav_playlist", %{"id" => id}, socket) do
    playlist = Music.get_playlist!(id)
    tracks = Music.list_tracks_for_playlist(playlist.id)

    {:noreply,
     socket
     |> assign(:nav_tab, :library)
     |> assign(:nav_context, :playlist)
     |> assign(:browse_filter, playlist)
     |> assign(:page, 1)
     |> assign(:track_count, length(tracks))
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> stream(:tracks, tracks, reset: true)}
  end

  @impl true
  def handle_event("nav_artists", _params, socket) do
    {:noreply,
     socket
     |> assign(:nav_tab, :browse)
     |> assign(:nav_context, :artist)
     |> assign(:browse_filter, nil)}
  end

  @impl true
  def handle_event("nav_artist", %{"name" => name}, socket) do
    scope = socket.assigns[:current_scope]
    filters = %{artist: name, status: "all"}

    tracks =
      list_tracks(scope,
        sort_by: socket.assigns.sort_by,
        page: 1,
        per_page: socket.assigns.per_page,
        filters: filters
      )

    {:noreply,
     socket
     |> assign(:nav_tab, :browse)
     |> assign(:nav_context, :artist)
     |> assign(:browse_filter, name)
     |> assign(:page, 1)
     |> assign(:filters, filters)
     |> assign(:track_count, length(tracks))
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> stream(:tracks, tracks, reset: true)}
  end

  @impl true
  def handle_event("nav_albums", _params, socket) do
    {:noreply,
     socket
     |> assign(:nav_tab, :browse)
     |> assign(:nav_context, :album)
     |> assign(:browse_filter, nil)}
  end

  @impl true
  def handle_event("nav_album", %{"name" => name}, socket) do
    scope = socket.assigns[:current_scope]
    filters = %{album: name, status: "all", artist: "all"}

    tracks =
      list_tracks(scope,
        sort_by: socket.assigns.sort_by,
        page: 1,
        per_page: socket.assigns.per_page,
        filters: filters
      )

    {:noreply,
     socket
     |> assign(:nav_tab, :browse)
     |> assign(:nav_context, :album)
     |> assign(:browse_filter, name)
     |> assign(:page, 1)
     |> assign(:filters, filters)
     |> assign(:track_count, length(tracks))
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> stream(:tracks, tracks, reset: true)}
  end

  @impl true
  def handle_event("new_playlist", _params, socket) do
    scope = socket.assigns[:current_scope]

    case Music.create_playlist(%{name: "New Playlist", user_id: user_id(socket)}) do
      {:ok, playlist} ->
        {:noreply,
         socket
         |> assign(:playlists, list_playlists(scope))
         |> assign(:nav_context, :playlist)
         |> assign(:browse_filter, playlist)
         |> assign(:track_count, 0)
         |> assign(:selected_ids, MapSet.new())
         |> assign(:select_all, false)
         |> stream(:tracks, [], reset: true)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create playlist")}
    end
  end

  @impl true
  def handle_event("page", %{"page" => page_str}, socket) do
    page =
      case Integer.parse(page_str) do
        {n, _} when n > 0 -> n
        _ -> 1
      end

    reload_tracks(socket, page: page)
  end

  @impl true
  def handle_event("fetch_spotify", %{"url" => url}, socket) do
    url = String.trim(url)

    if url == "" or not valid_spotify_url?(url) do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Please enter a valid Spotify URL (e.g. https://open.spotify.com/track/...)"
       )}
    else
      # Run SpotDL metadata fetch async to avoid blocking the LiveView process
      lv_pid = self()

      Task.Supervisor.async_nolink(SoundForge.TaskSupervisor, fn ->
        result = SoundForge.Audio.SpotDL.fetch_metadata(url)
        send(lv_pid, {:spotify_metadata, url, result})
      end)

      {:noreply, assign(socket, :fetching_spotify, true)}
    end
  end

  @impl true
  def handle_event("upload_audio", _params, socket) do
    uid = user_id(socket)

    uploaded_tracks =
      consume_uploaded_entries(socket, :audio, fn %{path: tmp_path}, entry ->
        process_uploaded_entry(tmp_path, entry, uid)
      end)

    successful =
      uploaded_tracks
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, track} -> track end)

    socket = Enum.reduce(successful, socket, &add_upload_pipeline(&2, &1))
    socket = upload_flash(socket, successful)
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :audio, ref)}
  end

  @impl true
  def handle_event("delete_track", %{"id" => id}, socket) do
    with {:ok, track} <- fetch_owned_track(socket, id),
         {:ok, _} <- Music.delete_track_with_files(track) do
      pipelines = Map.delete(socket.assigns.pipelines, id)

      socket =
        socket
        |> stream_delete_by_dom_id(:tracks, "tracks-#{id}")
        |> assign(:pipelines, pipelines)
        |> update(:track_count, fn c -> max(c - 1, 0) end)
        |> put_flash(:info, "Track deleted")

      socket =
        if socket.assigns.live_action == :show,
          do: push_navigate(socket, to: ~p"/"),
          else: socket

      {:noreply, socket}
    else
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Track not found")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to delete track")}
    end
  end

  @impl true
  def handle_event("dismiss_pipeline", %{"track-id" => track_id}, socket) do
    pipelines = Map.delete(socket.assigns.pipelines, track_id)
    {:noreply, assign(socket, :pipelines, pipelines)}
  end

  @valid_pipeline_stages ~w(download processing analysis)a

  @impl true
  def handle_event("retry_pipeline", %{"track-id" => track_id, "stage" => stage}, socket) do
    stage_atom =
      try do
        atom = String.to_existing_atom(stage)
        if atom in @valid_pipeline_stages, do: atom, else: nil
      rescue
        ArgumentError -> nil
      end

    if is_nil(stage_atom) do
      {:noreply, put_flash(socket, :error, "Invalid pipeline stage")}
    else
      user_id = socket.assigns[:current_user_id]

      with {:ok, track} <- fetch_owned_track(socket, track_id),
           {:ok, _} <- retry_pipeline_stage(track.id, stage_atom, user_id) do
        pipelines = socket.assigns.pipelines
        pipeline = Map.get(pipelines, track_id, %{})
        updated_pipeline = Map.put(pipeline, stage_atom, %{status: :queued, progress: 0})
        pipelines = Map.put(pipelines, track_id, updated_pipeline)

        {:noreply,
         socket
         |> assign(:pipelines, pipelines)
         |> put_flash(:info, "Retrying #{stage}...")}
      else
        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, "Track not found")}

        {:error, :no_completed_download} ->
          {:noreply, put_flash(socket, :error, "Download the track first")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Retry failed: #{reason}")}
      end
    end
  end

  # Async SpotDL metadata result
  @impl true
  def handle_info({:spotify_metadata, url, {:ok, tracks_data, playlist_meta}}, socket) do
    # Playlist import: create playlist record, then add tracks
    scope = socket.assigns[:current_scope]
    auto_download = socket.assigns.auto_download
    user_id = user_id(socket)

    playlist =
      case Music.get_playlist_by_spotify_id(playlist_meta["spotify_id"], user_id) do
        nil ->
          {:ok, pl} =
            Music.create_playlist(%{
              name: playlist_meta["name"] || "Untitled Playlist",
              spotify_id: playlist_meta["spotify_id"],
              cover_art_url: playlist_meta["cover"],
              spotify_url: url,
              user_id: user_id
            })

          pl

        existing ->
          existing
      end

    {socket, _pos} =
      tracks_data
      |> Enum.reduce({assign(socket, :spotify_url, ""), 0}, fn track_meta, {acc, pos} ->
        acc = add_pipeline_track(acc, track_meta, url, user_id, auto_download, playlist, pos)
        {acc, pos + 1}
      end)

    playlists = list_playlists(scope)
    msg = "Imported playlist \"#{playlist.name}\" with #{length(tracks_data)} tracks"

    {:noreply,
     socket
     |> assign(:fetching_spotify, false)
     |> assign(:playlists, playlists)
     |> put_flash(:info, msg)}
  end

  def handle_info({:spotify_metadata, url, {:ok, tracks_data}}, socket) do
    uid = user_id(socket)
    auto_download = socket.assigns.auto_download

    socket =
      tracks_data
      |> Enum.reduce(assign(socket, :spotify_url, ""), fn track_meta, acc ->
        add_pipeline_track(acc, track_meta, url, uid, auto_download)
      end)

    msg = fetch_success_message(tracks_data)
    {:noreply, socket |> assign(:fetching_spotify, false) |> put_flash(:info, msg)}
  end

  @impl true
  def handle_info({:spotify_metadata, _url, {:error, reason}}, socket) do
    {:noreply,
     socket |> assign(:fetching_spotify, false) |> put_flash(:error, "Failed: #{reason}")}
  end

  # Handle Task.Supervisor task failures (e.g., if spotdl process crashes)
  @impl true
  def handle_info({ref, _result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, :fetching_spotify, false)}
  end

  # Track-level pipeline progress (from workers)
  @impl true
  def handle_info({:pipeline_progress, %{track_id: track_id, stage: stage} = payload}, socket) do
    pipelines = socket.assigns.pipelines
    pipeline = Map.get(pipelines, track_id, %{})

    updated_pipeline =
      Map.put(pipeline, stage, %{status: payload.status, progress: payload.progress})

    pipelines = Map.put(pipelines, track_id, updated_pipeline)

    socket =
      if payload.status == :failed do
        stage_name = stage |> to_string() |> String.capitalize()
        put_flash(socket, :error, "#{stage_name} failed. Check server logs for details.")
      else
        socket
      end

    # When a stage completes and we're viewing this track, reload its detail data
    socket =
      if payload.status == :completed &&
           socket.assigns.live_action == :show &&
           socket.assigns.track && socket.assigns.track.id == track_id do
        track = Music.get_track_with_details!(track_id)

        socket
        |> assign(:track, track)
        |> assign(:stems, track.stems)
        |> assign(:analysis, List.first(track.analysis_results))
      else
        socket
      end

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

    # If viewing this track's detail, reload analysis and stems
    socket =
      if socket.assigns.live_action == :show &&
           socket.assigns.track && socket.assigns.track.id == track_id do
        track = Music.get_track_with_details!(track_id)

        socket
        |> assign(:track, track)
        |> assign(:stems, track.stems)
        |> assign(:analysis, List.first(track.analysis_results))
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:pipelines, pipelines)
     |> put_flash(:info, "Pipeline complete! Track is ready.")}
  end

  @impl true
  def handle_info({:job_progress, payload}, socket) do
    jobs = Map.put(socket.assigns.active_jobs, payload.job_id, payload)
    {:noreply, assign(socket, :active_jobs, jobs)}
  end

  # Notification forwarding to bell component
  @impl true
  def handle_info({:new_notification, _notification}, socket) do
    send_update(SoundForgeWeb.Live.Components.NotificationBell,
      id: "notification-bell",
      refresh: true
    )

    {:noreply, socket}
  end

  # Toast auto-dismiss forwarding
  @impl true
  def handle_info({:dismiss_toast, toast_id}, socket) do
    send_update(SoundForgeWeb.Live.Components.ToastStack,
      id: "toast-stack",
      dismiss: toast_id
    )

    {:noreply, socket}
  end

  # Spotify control messages from SpotifyPlayer component
  @impl true
  def handle_info(:spotify_pause, socket) do
    {:noreply, push_event(socket, "spotify_pause", %{})}
  end

  @impl true
  def handle_info(:spotify_resume, socket) do
    {:noreply, push_event(socket, "spotify_resume", %{})}
  end

  @impl true
  def handle_info({:spotify_seek, position_ms}, socket) do
    {:noreply, push_event(socket, "spotify_seek", %{position_ms: position_ms})}
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

  def format_duration(nil), do: ""

  def format_duration(ms) when is_integer(ms) do
    total_seconds = div(ms, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  def upload_error_to_string(:too_large), do: "File too large (max 100 MB)"
  def upload_error_to_string(:not_accepted), do: "Invalid file type"
  def upload_error_to_string(:too_many_files), do: "Too many files (max 5)"
  def upload_error_to_string(err), do: inspect(err)

  # -- Private helpers --

  defp start_single_pipeline(track_meta, original_url, uid, auto_download) do
    # spotdl uses "song_id" for the Spotify track ID
    spotify_id = track_meta["song_id"] || track_meta["id"]
    spotify_url = track_meta["url"] || original_url

    with :ok <- check_duplicate(spotify_id, nil),
         {:ok, track} <- create_track_from_metadata(track_meta, spotify_url, uid) do
      if auto_download do
        {:ok, download_job} = Music.create_download_job(%{track_id: track.id, status: :queued})

        %{
          "track_id" => track.id,
          "spotify_url" => spotify_url,
          "quality" => Settings.get(uid, :download_quality),
          "job_id" => download_job.id
        }
        |> SoundForge.Jobs.DownloadWorker.new()
        |> Oban.insert()

        pipeline = %{track_id: track.id, download: %{status: :queued, progress: 0}}
        {:ok, track, pipeline}
      else
        # auto_download disabled: create track record only, no download job
        pipeline = %{track_id: track.id}
        {:ok, track, pipeline}
      end
    end
  end

  defp add_pipeline_track(
         socket,
         track_meta,
         url,
         uid,
         auto_download,
         playlist \\ nil,
         position \\ nil
       ) do
    case start_single_pipeline(track_meta, url, uid, auto_download) do
      {:ok, track, pipeline} ->
        # Associate track with playlist if provided
        if playlist do
          Music.add_track_to_playlist(playlist, track, position || 0)
        end

        maybe_subscribe(socket, track.id)
        pipelines = Map.put(socket.assigns.pipelines, track.id, pipeline)

        socket
        |> assign(:pipelines, pipelines)
        |> stream_insert(:tracks, track, at: 0)
        |> update(:track_count, &(&1 + 1))

      {:error, _} ->
        socket
    end
  end

  defp maybe_subscribe(socket, track_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track_id}")
    end
  end

  defp fetch_success_message([_single | []] = [track_meta]) do
    "Started processing: #{track_meta["name"] || "track"}"
  end

  defp fetch_success_message(tracks_data) do
    "Started processing #{length(tracks_data)} tracks"
  end

  defp check_duplicate(nil, _scope), do: :ok

  defp check_duplicate(spotify_id, _scope) do
    case Music.get_track_by_spotify_id(spotify_id) do
      nil -> :ok
      _track -> {:error, :duplicate}
    end
  end

  defp process_uploaded_entry(tmp_path, entry, user_id) do
    filename = entry.client_name
    title = filename |> Path.rootname() |> String.replace(~r/[-_]+/, " ") |> String.trim()
    ext = Path.extname(filename)

    SoundForge.Storage.ensure_directories!()
    dest_filename = "#{Ecto.UUID.generate()}#{ext}"
    dest_path = Path.join(SoundForge.Storage.downloads_path(), dest_filename)
    File.cp!(tmp_path, dest_path)

    case Music.create_track(%{title: title, user_id: user_id}) do
      {:ok, track} ->
        enqueue_upload_processing(track, dest_path, entry.client_size)
        {:ok, track}

      error ->
        File.rm(dest_path)
        error
    end
  end

  defp enqueue_upload_processing(track, dest_path, file_size) do
    {:ok, _job} =
      Music.create_download_job(%{
        track_id: track.id,
        status: :completed,
        output_path: dest_path,
        file_size: file_size
      })

    model = Settings.get(nil, :demucs_model)

    {:ok, processing_job} =
      Music.create_processing_job(%{track_id: track.id, model: model, status: :queued})

    %{
      "track_id" => track.id,
      "job_id" => processing_job.id,
      "file_path" => dest_path,
      "model" => model
    }
    |> SoundForge.Jobs.ProcessingWorker.new()
    |> Oban.insert()
  end

  defp add_upload_pipeline(socket, track) do
    maybe_subscribe(socket, track.id)

    pipeline = %{
      track_id: track.id,
      download: %{status: :completed, progress: 100},
      processing: %{status: :queued, progress: 0}
    }

    pipelines = Map.put(socket.assigns.pipelines, track.id, pipeline)

    socket
    |> assign(:pipelines, pipelines)
    |> stream_insert(:tracks, track, at: 0)
    |> update(:track_count, &(&1 + 1))
  end

  defp upload_flash(socket, []), do: socket

  defp upload_flash(socket, [_]),
    do: put_flash(socket, :info, "Uploaded 1 file, processing started")

  defp upload_flash(socket, tracks),
    do: put_flash(socket, :info, "Uploaded #{length(tracks)} files, processing started")

  defp scope_user_id(%{user: %{id: id}}), do: id
  defp scope_user_id(_), do: nil

  # Reliable user_id resolution: scope first, then socket assigns fallback
  defp user_id(socket) do
    scope_user_id(socket.assigns[:current_scope]) || socket.assigns[:current_user_id]
  end

  defp subscribe_to_track(socket, track) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")

      Enum.each(track.stems, fn stem ->
        Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{stem.processing_job_id}")
      end)
    end
  end

  defp socket_user_id(socket) do
    socket.assigns[:current_user_id]
  end

  defp resolve_user_id(%{user: %{id: id}}, _session), do: id

  defp resolve_user_id(_, session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _inserted_at} <- SoundForge.Accounts.get_user_by_session_token(token) do
      user.id
    else
      _ -> nil
    end
  end

  defp owns_track?(socket, track) do
    user_id = socket_user_id(socket)
    is_nil(track.user_id) or track.user_id == user_id
  end

  defp fetch_owned_track(socket, track_id) do
    case Music.get_track(track_id) do
      {:ok, track} when not is_nil(track) ->
        if owns_track?(socket, track), do: {:ok, track}, else: {:error, :not_found}

      _ ->
        {:error, :not_found}
    end
  end

  defp create_track_from_metadata(metadata, spotify_url, user_id) do
    # spotdl metadata format:
    #   name, artists (list of strings), album_name, album_artist,
    #   song_id, duration (seconds), cover_url, url
    attrs = %{
      title: metadata["name"] || "Unknown",
      artist: extract_artist(metadata),
      album: normalize_string(metadata["album_name"] || metadata["album"]),
      album_art_url: metadata["cover_url"],
      spotify_id: metadata["song_id"] || metadata["id"],
      spotify_url: spotify_url,
      duration: normalize_duration(metadata["duration"]),
      user_id: user_id
    }

    Music.create_track(attrs)
  end

  # spotdl returns artists as a list of strings
  defp extract_artist(%{"artists" => [name | _]}) when is_binary(name), do: name
  # Spotify API format fallback (list of objects)
  defp extract_artist(%{"artists" => [%{"name" => name} | _]}), do: name
  defp extract_artist(%{"artist" => artist}) when is_binary(artist), do: artist
  defp extract_artist(_), do: nil

  # spotdl returns duration in seconds; we store milliseconds
  defp normalize_duration(seconds) when is_number(seconds), do: round(seconds * 1000)
  defp normalize_duration(_), do: nil

  # Normalize empty strings to nil for optional fields
  defp normalize_string(""), do: nil
  defp normalize_string(s) when is_binary(s), do: s
  defp normalize_string(_), do: nil

  defp valid_spotify_url?(url) do
    Regex.match?(~r{spotify\.com/(track|album|playlist)/[a-zA-Z0-9]+}, url)
  end

  defp list_tracks(scope, opts \\ [])

  defp list_tracks(scope, opts) when is_map(scope) and not is_nil(scope) do
    Music.list_tracks(scope, opts)
  rescue
    _ -> []
  end

  defp list_tracks(_scope, opts) do
    Music.list_tracks(opts)
  rescue
    _ -> []
  end

  defp search_tracks(query, scope)
       when byte_size(query) > 0 and is_map(scope) and not is_nil(scope) do
    Music.search_tracks(query, scope)
  rescue
    _ -> list_tracks(scope)
  end

  defp search_tracks(query, _scope) when byte_size(query) > 0 do
    Music.search_tracks(query)
  rescue
    _ -> list_tracks(nil)
  end

  defp search_tracks(_, scope), do: list_tracks(scope)

  def pagination_range(_current_page, total) when total <= 7, do: 1..total |> Enum.to_list()

  def pagination_range(current_page, total) do
    start_page = max(1, current_page - 2)
    end_page = min(total, start_page + 4)
    start_page = max(1, end_page - 4)
    Enum.to_list(start_page..end_page)
  end

  defp count_tracks(scope) when is_map(scope) and not is_nil(scope) do
    Music.count_tracks(scope)
  rescue
    _ -> 0
  end

  defp count_tracks(_scope) do
    Music.count_tracks()
  rescue
    _ -> 0
  end

  defp per_page(user_id), do: Settings.get(user_id, :tracks_per_page)

  defp total_pages(track_count, per_page) when per_page > 0 do
    max(1, ceil(track_count / per_page))
  end

  defp total_pages(_, _), do: 1

  defp retry_pipeline_stage(track_id, :download, user_id) do
    track = Music.get_track!(track_id)

    with {:ok, job} <- Music.create_download_job(%{track_id: track_id, status: :queued}) do
      %{
        "track_id" => track_id,
        "spotify_url" => track.spotify_url,
        "quality" => Settings.get(user_id, :download_quality),
        "job_id" => job.id
      }
      |> SoundForge.Jobs.DownloadWorker.new()
      |> Oban.insert()
    end
  end

  defp retry_pipeline_stage(track_id, :processing, user_id) do
    model = Settings.get(user_id, :demucs_model)

    with {:ok, file_path} <- Music.get_download_path(track_id),
         {:ok, job} <-
           Music.create_processing_job(%{track_id: track_id, model: model, status: :queued}) do
      %{
        "track_id" => track_id,
        "job_id" => job.id,
        "file_path" => file_path,
        "model" => model
      }
      |> SoundForge.Jobs.ProcessingWorker.new()
      |> Oban.insert()
    else
      {:error, :no_completed_download} -> {:error, :no_completed_download}
      error -> error
    end
  end

  defp retry_pipeline_stage(track_id, :analysis, user_id) do
    with {:ok, file_path} <- Music.get_download_path(track_id),
         {:ok, job} <- Music.create_analysis_job(%{track_id: track_id, status: :queued}) do
      %{
        "track_id" => track_id,
        "job_id" => job.id,
        "file_path" => file_path,
        "features" => Settings.get(user_id, :analysis_features)
      }
      |> SoundForge.Jobs.AnalysisWorker.new()
      |> Oban.insert()
    else
      {:error, :no_completed_download} -> {:error, :no_completed_download}
      error -> error
    end
  end

  defp reload_tracks(socket, overrides) do
    scope = socket.assigns[:current_scope]
    sort_by = Keyword.get(overrides, :sort_by, socket.assigns.sort_by)
    page = Keyword.get(overrides, :page, socket.assigns.page)
    per_page = socket.assigns.per_page
    filters = Keyword.get(overrides, :filters, socket.assigns.filters)

    tracks =
      list_tracks(scope, sort_by: sort_by, page: page, per_page: per_page, filters: filters)

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:page, page)
     |> assign(:filters, filters)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> stream(:tracks, tracks, reset: true)}
  end

  defp list_artists(scope) when is_map(scope) and not is_nil(scope) do
    Music.list_distinct_artists(scope)
  rescue
    _ -> []
  end

  defp list_artists(_scope) do
    Music.list_distinct_artists()
  rescue
    _ -> []
  end

  defp list_playlists(scope) when is_map(scope) and not is_nil(scope) do
    Music.list_playlists(scope)
  rescue
    _ -> []
  end

  defp list_playlists(_), do: []

  defp list_albums(scope) when is_map(scope) and not is_nil(scope) do
    Music.list_distinct_albums(scope)
  rescue
    _ -> []
  end

  defp list_albums(_), do: []

  defp delete_single_track(socket, track_id) do
    with {:ok, track} <- fetch_owned_track(socket, track_id),
         {:ok, _} <- Music.delete_track_with_files(track) do
      pipelines = Map.delete(socket.assigns.pipelines, track_id)

      socket
      |> stream_delete_by_dom_id(:tracks, "tracks-#{track_id}")
      |> assign(:pipelines, pipelines)
      |> update(:track_count, fn c -> max(c - 1, 0) end)
    else
      _ -> socket
    end
  end

  defp has_completed_download?(track_id) do
    import Ecto.Query

    SoundForge.Repo.exists?(
      from(dj in SoundForge.Music.DownloadJob,
        where: dj.track_id == ^track_id and dj.status == :completed
      )
    )
  end

  defp spotify_linked?(nil), do: false

  defp spotify_linked?(user_id) do
    SoundForge.Spotify.OAuth.linked?(user_id)
  rescue
    _ -> false
  end
end
