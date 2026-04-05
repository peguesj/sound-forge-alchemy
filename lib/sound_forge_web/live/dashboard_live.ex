defmodule SoundForgeWeb.DashboardLive do
  @moduledoc """
  Main dashboard LiveView for track management, pipeline control, and audio playback.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Music
  alias SoundForge.Notifications
  alias SoundForge.Settings
  alias SoundForge.Audio.AnalysisHelpers
  alias SoundForge.Audio.LalalAI
  alias SoundForge.Audio.Prefetch
  alias SoundForge.MIDI.NoteEdits

  require Logger

  @max_debug_logs 500
  @max_midi_log 50

  use SoundForgeWeb.Live.Handlers.MidiHandlers
  use SoundForgeWeb.Live.Handlers.DebugHandlers
  use SoundForgeWeb.Live.Handlers.PipelineHandlers

  @impl true
  def mount(_params, session, socket) do
    scope = socket.assigns[:current_scope] || load_scope_from_session(session)
    current_user_id = resolve_user_id(scope, session)

    socket =
      socket
      |> assign(:current_scope, scope)
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
      |> assign(:midi_result, nil)
      |> assign(:chord_result, nil)
      |> assign(:user_notes, [])
      |> assign(:sort_by, :newest)
      |> assign(:view_mode, :grid)
      |> assign(:filters, %{status: "all", artist: "all"})
      |> assign(:artists, list_artists(scope))
      |> assign(:selected_ids, MapSet.new())
      |> assign(:select_all, false)
      |> assign(:select_all_pages, false)
     |> assign(:select_all_pages, false)
      |> assign(:select_all_pages, false)
      |> assign(:batch_mode, false)
      |> assign(:batch_processing, false)
      |> assign(:batch_status, nil)
      |> assign(:show_batch_modal, false)
      |> assign(:auto_download, true)
      |> assign(:editing_track, nil)
      |> assign(:spotify_playback, nil)
      |> assign(:spotify_linked, spotify_linked?(current_user_id))
      |> assign(:spotify_premium, true)
      |> assign(:spotify_alchemy_playing, false)
      |> assign(:nav_tab, :library)
      |> assign(:nav_context, :all_tracks)
      |> assign(:browse_filter, nil)
      |> assign(:playlists, list_playlists(scope))
      |> assign(:albums, list_albums(scope))
      |> assign(:selected_source, nil)
      |> assign(:source_sample_type_filter, nil)
      |> assign(:page, 1)
      |> assign(:per_page, per_page(current_user_id))
      |> assign(:selected_engine, "demucs")
      |> assign(:preview_mode, false)
      |> assign(:show_lalalai_modal, false)
      |> assign(:show_midi_settings_modal, false)
      |> assign(:refreshing_midi, false)
      |> assign(:show_transients, false)
      |> assign(:lalalai_modal_expanded, false)
      |> assign(:lalalai_modal_key_input, "")
      |> assign(:lalalai_modal_testing, false)
      |> assign(:lalalai_modal_test_result, nil)
      |> assign(:lalalai_last_error, nil)
      |> assign(:lalalai_connection_status, nil)
      |> assign(:lalalai_mode, "stem_separator")
      |> assign(:multistem_selection, MapSet.new())
      |> assign(:noise_level, 0)
      |> assign(:voice_pack_id, nil)
      |> assign(:accent, 0.5)
      |> assign(:dereverb, false)
      |> assign(:debug_mode, Settings.get(current_user_id, :debug_mode) || false)
      |> assign(:drawer_open, false)
      |> assign(:debug_panel_open, false)
      |> assign(:debug_tab, :logs)
      |> assign(:debug_workers_open, false)
      |> assign(:debug_queue_open, false)
      |> assign(:debug_logs, [])
      |> assign(:debug_log_filter_level, "all")
      |> assign(:debug_log_filter_ns, "all")
      |> assign(:debug_log_search, "")
      |> assign(:debug_log_namespaces, MapSet.new())
      |> assign(:midi_devices, [])
      |> assign(:midi_bpm, nil)
      |> assign(:last_bpm_ms, System.monotonic_time(:millisecond))
      |> assign(:midi_transport, :stopped)
      |> assign(:midi_log, [])
      |> assign(:midi_monitor_open, false)
      |> assign(:midi_monitor_listening, false)
      |> assign(:midi_tailf, false)
      |> assign(:midi_raw_log, [])
      |> assign(:midi_learn_active, false)
      |> assign(:midi_bar_position, "bottom")
      |> assign(:trace_jobs, [])
      |> assign(:trace_selected_job, nil)
      |> assign(:trace_timeline, [])
      |> assign(:trace_graph, %{nodes: [], links: []})
      # DevTools tab state
      |> assign(:devtools_render_count, 0)
      |> assign(:devtools_event_count, 0)
      |> assign(:devtools_last_refreshed, nil)
      |> assign(:devtools_pubsub_topics, [])
      |> assign(:devtools_socket_summary, %{})
      # UAT tab state
      |> assign(:uat_scenarios, initial_uat_scenarios())
      |> assign(:uat_running, nil)
      |> assign(:uat_log, [])
      |> assign(:worker_stats, [])
      |> assign(:queue_tab, :active)
      |> assign(:queue_active_jobs, [])
      |> assign(:queue_history_jobs, [])
      |> assign(:queue_history_has_more, false)
      |> assign(:daw_track_id, nil)
      |> assign(:daw_library_open, false)
      |> assign(:dj_library_open, false)
      |> assign(:analysis_library_open, false)
      |> allow_upload(:audio,
        accept: ~w(.mp3 .wav .flac .ogg .m4a .aac .wma),
        max_entries: 5,
        max_file_size: Settings.get(current_user_id, :max_upload_size)
      )
      |> stream(:tracks, list_tracks(scope, page: 1, per_page: per_page(current_user_id)))

    socket =
      if connected?(socket) and current_user_id do
        SoundForge.Notifications.subscribe(current_user_id)

        # Subscribe to debug streams and load initial data if debug mode is enabled
        socket =
          if Settings.get(current_user_id, :debug_mode) do
            Phoenix.PubSub.subscribe(SoundForge.PubSub, SoundForge.Debug.LogBroadcaster.topic())
            Phoenix.PubSub.subscribe(SoundForge.PubSub, SoundForge.Telemetry.ObanHandler.worker_status_topic())
            socket
            |> assign(:worker_stats, SoundForge.Debug.Jobs.worker_stats())
            |> assign(:queue_active_jobs, SoundForge.Debug.Jobs.active_jobs())
            |> load_queue_history()
          else
            socket
          end

        # Subscribe to Chef PubSub topics for recipe progress/completion
        SoundForgeWeb.Endpoint.subscribe("chef:#{current_user_id}")

        # Subscribe to MIDI PubSub topics
        Phoenix.PubSub.subscribe(SoundForge.PubSub, "midi:devices")
        Phoenix.PubSub.subscribe(SoundForge.PubSub, "midi:clock")
        Phoenix.PubSub.subscribe(SoundForge.PubSub, "midi:actions")

        # Initialize MIDI state from current device/clock state
        socket =
          socket
          |> assign(:midi_devices, safe_list_midi_devices())
          |> assign(:midi_bpm, safe_get_midi_bpm())
          |> assign(:midi_transport, safe_get_midi_transport())

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
       |> assign(:analysis, analysis)
       |> assign(:midi_result, Music.get_midi_result_for_track(id))
       |> assign(:chord_result, Music.get_chord_result_for_track(id))
       |> assign(:user_notes, serialize_user_notes(NoteEdits.list_note_edits(id, socket.assigns.current_user_id)))}
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

  def handle_params(%{"tab" => "dj", "activate_set_id" => set_id}, _uri, socket) do
    Prefetch.prefetch_for_dj(socket.assigns[:current_user_id])

    socket =
      socket
      |> assign(:live_action, :index)
      |> assign(:nav_tab, :dj)
      |> assign(:nav_context, :dj)

    if connected?(socket) do
      send_update(SoundForgeWeb.Live.Components.DjTabComponent,
        id: "dj-tab-root",
        activate_performance_set_id: set_id
      )
    end

    {:noreply, socket}
  end

  def handle_params(%{"tab" => "dj", "set_id" => set_id}, _uri, socket) do
    Prefetch.prefetch_for_dj(socket.assigns[:current_user_id])

    socket =
      socket
      |> assign(:live_action, :index)
      |> assign(:nav_tab, :dj)
      |> assign(:nav_context, :dj)

    if connected?(socket) do
      send_update(SoundForgeWeb.Live.Components.DjTabComponent,
        id: "dj-tab-root",
        show_performance_set_id: set_id
      )
    end

    {:noreply, socket}
  end

  def handle_params(%{"tab" => "dj"}, _uri, socket) do
    # Async prefetch DJ metadata -- does not block tab switch
    Prefetch.prefetch_for_dj(socket.assigns[:current_user_id])

    {:noreply,
     socket
     |> assign(:live_action, :index)
     |> assign(:nav_tab, :dj)
     |> assign(:nav_context, :dj)}
  end

  def handle_params(%{"tab" => "daw", "track_id" => track_id}, _uri, socket) do
    # Async prefetch DAW stem metadata -- does not block tab switch
    Prefetch.prefetch_for_daw(socket.assigns[:current_user_id])

    {:noreply,
     socket
     |> assign(:live_action, :index)
     |> assign(:nav_tab, :daw)
     |> assign(:nav_context, :daw)
     |> assign(:daw_track_id, track_id)}
  end

  def handle_params(%{"tab" => "daw"}, _uri, socket) do
    # Async prefetch DAW stem metadata -- does not block tab switch
    Prefetch.prefetch_for_daw(socket.assigns[:current_user_id])

    {:noreply,
     socket
     |> assign(:live_action, :index)
     |> assign(:nav_tab, :daw)
     |> assign(:nav_context, :daw)
     |> assign(:daw_track_id, nil)}
  end

  def handle_params(%{"tab" => "pads"}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:live_action, :index)
     |> assign(:nav_tab, :pads)
     |> assign(:nav_context, :pads)}
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
       |> assign(:select_all, false)
       |> assign(:select_all_pages, false)}
    else
      # Default: select ALL tracks across all pages
      scope = socket.assigns[:current_scope]
      sort_by = socket.assigns.sort_by

      all_track_ids =
        list_tracks(scope, sort_by: sort_by, page: 1, per_page: 10_000)
        |> Enum.map(& &1.id)
        |> MapSet.new()

      {:noreply,
       socket
       |> assign(:selected_ids, all_track_ids)
       |> assign(:select_all, true)
       |> assign(:select_all_pages, true)}
    end
  end

  @impl true
  def handle_event("select_all_pages", _params, socket) do
    scope = socket.assigns[:current_scope]
    sort_by = socket.assigns.sort_by

    # Select ALL track IDs across all pages
    all_track_ids =
      list_tracks(scope, sort_by: sort_by, page: 1, per_page: 10_000)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    {:noreply,
     socket
     |> assign(:selected_ids, all_track_ids)
     |> assign(:select_all, true)
     |> assign(:select_all_pages, true)}
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
     |> assign(:select_all_pages, false)
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
     |> assign(:select_all_pages, false)
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
     |> assign(:select_all_pages, false)
     |> put_flash(:info, "Deleted #{count} tracks")}
  end


  # -- Batch Mode (BatchProcessor integration) --

  @impl true
  def handle_event("toggle_batch_mode", _params, socket) do
    new_mode = !socket.assigns.batch_mode

    socket =
      socket
      |> assign(:batch_mode, new_mode)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:select_all, false)
      |> assign(:select_all_pages, false)
     |> assign(:select_all_pages, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_track_select", %{"track_id" => track_id}, socket) do
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, track_id) do
        MapSet.delete(selected, track_id)
      else
        MapSet.put(selected, track_id)
      end

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("start_batch_process", _params, socket) do
    {:noreply, assign(socket, :show_batch_modal, true)}
  end

  @impl true
  def handle_event("cancel_batch_modal", _params, socket) do
    {:noreply, assign(socket, :show_batch_modal, false)}
  end

  @impl true
  def handle_event("confirm_batch_process", %{"engine" => engine, "stem_filter" => stem_filter}, socket) do
    user_id = socket.assigns[:current_user_id]
    track_ids = MapSet.to_list(socket.assigns.selected_ids)

    case SoundForge.Audio.BatchProcessor.start_batch(
           track_ids: track_ids,
           user_id: user_id,
           stem_filter: stem_filter,
           engine_opts: [splitter: engine]
         ) do
      {:ok, %{batch_job: batch_job}} ->
        Phoenix.PubSub.subscribe(SoundForge.PubSub, "batch:\#{batch_job.id}")

        {:noreply,
         socket
         |> assign(:batch_processing, true)
         |> assign(:batch_status, batch_job)
         |> assign(:show_batch_modal, false)
         |> assign(:selected_ids, MapSet.new())
         |> assign(:select_all, false)
      |> assign(:select_all_pages, false)
     |> assign(:select_all_pages, false)
         |> put_flash(:info, "Batch processing started for \#{length(track_ids)} tracks")}

      {:error, :empty_batch} ->
        {:noreply, put_flash(socket, :error, "No tracks selected for batch processing")}

      {:error, {:batch_too_large, msg}} ->
        {:noreply, put_flash(socket, :error, msg)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Batch processing failed: #{inspect(reason)}")}
    end
  end

  # -- Download Actions --

  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
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
     |> assign(:select_all_pages, false)
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

  # -- Playback Routing --

  @impl true
  def handle_event("play_track", %{"id" => id}, socket) do
    with {:ok, track} <- fetch_owned_track(socket, id) do
      # Priority order:
      # 1. Local downloaded file (if exists)
      # 2. Local stems (if exists)
      # 3. Spotify Web Playback (fallback)

      cond do
        # Check if we have a completed download with local file
        track.download_status == "completed" ->
          case Music.get_download_path(track.id) do
            {:ok, local_path} when not is_nil(local_path) ->
              # Verify file exists before navigating
              if File.exists?(local_path) do
                {:noreply, push_navigate(socket, to: ~p"/tracks/#{track.id}")}
              else
                # File missing, fall back to Spotify
                uri = "spotify:track:#{track.spotify_id}"
                handle_event("play_spotify", %{"uri" => uri}, socket)
              end
            _ ->
              # No download path, try stems or Spotify
              if Music.count_stems(track.id) > 0 do
                {:noreply, push_navigate(socket, to: ~p"/tracks/#{track.id}")}
              else
                uri = "spotify:track:#{track.spotify_id}"
                handle_event("play_spotify", %{"uri" => uri}, socket)
              end
          end

        # Check if we have stems (stem separation completed)
        Music.count_stems(track.id) > 0 ->
          {:noreply, push_navigate(socket, to: ~p"/tracks/#{track.id}")}

        # Fall back to Spotify Web Playback
        true ->
          uri = "spotify:track:#{track.spotify_id}"
          handle_event("play_spotify", %{"uri" => uri}, socket)
      end
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Track not found")}
    end
  end

  # -- Spotify Playback --

  @impl true
  def handle_event("play_spotify", %{"uri" => uri}, socket) do
    user_id = socket.assigns[:current_user_id]

    case SoundForge.Spotify.OAuth.get_valid_access_token(user_id) do
      {:ok, token} ->
        {:noreply,
         socket
         |> assign(:spotify_alchemy_playing, true)
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
      duration_ms: params["duration_ms"] || 0,
      track_uri: params["track_uri"],
      context_type: params["context_type"],
      context_uri: params["context_uri"]
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

    {:noreply, push_notification(socket, toast_type, "Spotify", message)}
  end

  def handle_event("spotify_error", %{"message" => message}, socket) do
    send_update(SoundForgeWeb.Live.Components.ToastStack,
      id: "toast-stack",
      toast: %{type: :error, title: "Spotify", message: message}
    )

    {:noreply, push_notification(socket, :error, "Spotify", message)}
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
  def handle_event("nav_tab", %{"tab" => "home"}, socket) do
    {:noreply, assign(socket, :nav_tab, :home)}
  end

  def handle_event("nav_tab", %{"tab" => "library"}, socket) do
    SoundForge.ControlSurface.ActionBus.set_active_tab("library")

    socket =
      socket
      |> assign(:nav_tab, :library)
      |> assign(:nav_context, :all_tracks)
      |> assign(:browse_filter, nil)
      |> assign(:page, 1)
      |> assign(:filters, %{status: "all", artist: "all"})
      |> assign(:selected_ids, MapSet.new())
      |> assign(:select_all, false)
      |> assign(:select_all_pages, false)

    reload_tracks(socket, page: 1, filters: %{status: "all", artist: "all"})
  end

  def handle_event("nav_tab", %{"tab" => "browse"}, socket) do
    {:noreply,
     socket
     |> assign(:nav_tab, :browse)
     |> assign(:nav_context, :artist)
     |> assign(:browse_filter, nil)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> assign(:select_all_pages, false)}
  end

  def handle_event("nav_tab", %{"tab" => "dj"}, socket) do
    # Kick off prefetch early -- push_patch will trigger handle_params too,
    # but starting here shaves off the round-trip latency.
    Prefetch.prefetch_for_dj(socket.assigns[:current_user_id])
    SoundForge.ControlSurface.ActionBus.set_active_tab("dj")

    {:noreply,
     socket
     |> assign(:nav_tab, :dj)
     |> assign(:nav_context, :dj)
     |> push_patch(to: ~p"/?#{[tab: "dj"]}")}
  end

  def handle_event("nav_tab", %{"tab" => "daw"}, socket) do
    Prefetch.prefetch_for_daw(socket.assigns[:current_user_id])
    SoundForge.ControlSurface.ActionBus.set_active_tab("daw")

    {:noreply,
     socket
     |> assign(:nav_tab, :daw)
     |> assign(:nav_context, :daw)
     |> push_patch(to: ~p"/?#{[tab: "daw"]}")}
  end

  def handle_event("nav_tab", %{"tab" => "pads"}, socket) do
    {:noreply,
     socket
     |> assign(:nav_tab, :pads)
     |> assign(:nav_context, :pads)
     |> push_patch(to: ~p"/?#{[tab: "pads"]}")}
  end

  # MARK: — Library pullout handlers (US-B01 to US-B04)

  def handle_event("open_in_daw", %{"track-id" => track_id}, socket) do
    {:noreply,
     socket
     |> assign(:nav_tab, :daw)
     |> assign(:nav_context, :daw)
     |> assign(:daw_track_id, track_id)
     |> assign(:daw_library_open, true)
     |> push_patch(to: ~p"/?#{[tab: "daw", track_id: track_id]}")}
  end

  def handle_event("toggle_daw_library", _params, socket) do
    {:noreply, assign(socket, :daw_library_open, !socket.assigns.daw_library_open)}
  end

  def handle_event("toggle_dj_library", _params, socket) do
    {:noreply, assign(socket, :dj_library_open, !socket.assigns.dj_library_open)}
  end

  def handle_event("toggle_analysis_library", _params, socket) do
    {:noreply, assign(socket, :analysis_library_open, !socket.assigns.analysis_library_open)}
  end

  def handle_event("daw_load_from_library", %{"track-id" => track_id}, socket) do
    {:noreply,
     socket
     |> assign(:daw_track_id, track_id)
     |> assign(:daw_library_open, false)}
  end

  @impl true
  def handle_event("load_in_pads", %{"track-id" => track_id}, socket) do
    socket =
      socket
      |> assign(:nav_tab, :pads)
      |> assign(:nav_context, :pads)
      |> push_patch(to: ~p"/?#{[tab: "pads"]}")

    send_update(SoundForgeWeb.Live.Components.ChromaticPadsComponent,
      id: "pads-tab",
      auto_load_track_id: track_id
    )

    {:noreply, socket}
  end

  def handle_event("nav_tab", %{"tab" => _unknown}, socket) do
    {:noreply, socket}
  end

  # -- Keyboard delegation to DJ component --

  @impl true
  def handle_event("keydown", %{"key" => "p", "metaKey" => true} = _params, socket) do
    # Cmd+P (macOS) toggles Pads view -- prevent default browser print dialog via JS
    {:noreply,
     socket
     |> assign(:nav_tab, :pads)
     |> assign(:nav_context, :pads)
     |> push_patch(to: ~p"/?#{[tab: "pads"]}")}
  end

  def handle_event("keydown", %{"key" => "p", "ctrlKey" => true} = _params, socket) do
    # Ctrl+P (Linux/Windows) toggles Pads view
    {:noreply,
     socket
     |> assign(:nav_tab, :pads)
     |> assign(:nav_context, :pads)
     |> push_patch(to: ~p"/?#{[tab: "pads"]}")}
  end

  def handle_event("keydown", params, %{assigns: %{nav_tab: :dj}} = socket) do
    send_update(SoundForgeWeb.Live.Components.DjTabComponent,
      id: "dj-tab-root",
      keydown: params
    )

    {:noreply, socket}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer_open, true)}
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer_open, false)}
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
      |> push_patch(to: ~p"/")

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
     |> assign(:select_all_pages, false)
     |> stream(:tracks, tracks, reset: true)
     |> push_patch(to: ~p"/")}
  end

  @impl true
  def handle_event("nav_playlist", %{"id" => id}, socket) do
    playlist = Music.get_playlist!(id)
    tracks = Music.list_playlist_tracks_with_status(playlist.id)

    # Subscribe to playlist-level pipeline topic for real-time batch updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "playlist_pipeline:#{playlist.id}")
      # Subscribe to each track's individual topic so existing handlers fire
      Enum.each(tracks, fn track ->
        Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")
      end)
    end

    # Merge DB-derived initial pipeline state into existing pipelines assign
    initial_pipelines =
      Enum.reduce(tracks, socket.assigns.pipelines, fn track, acc ->
        pipeline = build_initial_pipeline(track)
        if map_size(pipeline) > 0, do: Map.put(acc, track.id, pipeline), else: acc
      end)

    # Auto-resume any tracks that are partially complete (download done, analysis missing)
    user_id = socket.assigns[:current_user_id]
    maybe_resume_incomplete_pipelines(tracks, user_id)

    {:noreply,
     socket
     |> assign(:nav_tab, :library)
     |> assign(:nav_context, :playlist)
     |> assign(:browse_filter, playlist)
     |> assign(:page, 1)
     |> assign(:track_count, length(tracks))
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> assign(:select_all_pages, false)
     |> assign(:pipelines, initial_pipelines)
     |> stream(:tracks, tracks, reset: true)
     |> push_patch(to: ~p"/")}
  end

  @impl true
  def handle_event("nav_source", %{"source" => source}, socket) do
    scope = socket.assigns[:current_scope]
    tracks = Music.list_tracks_by_source_and_type(scope, source, nil)

    {:noreply,
     socket
     |> assign(:nav_tab, :library)
     |> assign(:nav_context, :source)
     |> assign(:selected_source, source)
     |> assign(:source_sample_type_filter, nil)
     |> assign(:browse_filter, nil)
     |> assign(:page, 1)
     |> assign(:track_count, length(tracks))
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> assign(:select_all_pages, false)
     |> stream(:tracks, tracks, reset: true)
     |> push_patch(to: ~p"/")}
  end

  @impl true
  def handle_event("nav_source_type", %{"sample_type" => sample_type}, socket) do
    scope = socket.assigns[:current_scope]
    source = socket.assigns[:selected_source]
    type_filter = if sample_type == "", do: nil, else: sample_type
    tracks = Music.list_tracks_by_source_and_type(scope, source, type_filter)

    {:noreply,
     socket
     |> assign(:source_sample_type_filter, type_filter)
     |> assign(:page, 1)
     |> assign(:track_count, length(tracks))
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)
     |> assign(:select_all_pages, false)
     |> stream(:tracks, tracks, reset: true)}
  end

  def handle_event("toggle_transients", _params, socket) do
    {:noreply, assign(socket, :show_transients, !socket.assigns.show_transients)}
  end

  @impl true
  def handle_event("nav_artists", _params, socket) do
    {:noreply,
     socket
     |> assign(:nav_tab, :browse)
     |> assign(:nav_context, :artist)
     |> assign(:browse_filter, nil)
     |> push_patch(to: ~p"/")}
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
     |> assign(:select_all_pages, false)
     |> stream(:tracks, tracks, reset: true)}
  end

  @impl true
  def handle_event("nav_albums", _params, socket) do
    {:noreply,
     socket
     |> assign(:nav_tab, :browse)
     |> assign(:nav_context, :album)
     |> assign(:browse_filter, nil)
     |> push_patch(to: ~p"/")}
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
     |> assign(:select_all_pages, false)
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
      |> assign(:select_all_pages, false)
     |> assign(:select_all_pages, false)
         |> stream(:tracks, [], reset: true)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create playlist")}
    end
  end

  # -- Debug Panel --

  @impl true
  @impl true
  @valid_debug_tabs ~w(logs tracing midi devtools uat)a

  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  # MIDI Monitor (always-available floating panel)
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  # ── DevTools Tab Events ──────────────────────────────────────────────

  @impl true
  @impl true
  @impl true
  @impl true
  # ── UAT Tab Events ──────────────────────────────────────────────────

  @impl true
  @impl true
  @impl true
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
  @impl true
  @impl true
  @impl true
  @impl true
  @valid_pipeline_stages ~w(download processing analysis)a

  @impl true
  @impl true
  # Piano Roll note editing (Story 2.4)
  @impl true
  def handle_event("add_user_note", %{"note" => note, "onset_sec" => onset_sec, "duration_sec" => duration_sec, "velocity" => velocity}, socket) do
    track = socket.assigns.track
    user_id = socket.assigns.current_user_id

    if track && user_id do
      case NoteEdits.create_note_edit(%{
        note: note,
        onset_sec: onset_sec,
        duration_sec: duration_sec,
        velocity: velocity,
        track_id: track.id,
        user_id: user_id
      }) do
        {:ok, _edit} ->
          user_notes = serialize_user_notes(NoteEdits.list_note_edits(track.id, user_id))
          {:noreply,
           socket
           |> assign(:user_notes, user_notes)
           |> push_event("set_user_notes", %{notes: user_notes})}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  # Catch-all for events bubbled from child components (e.g. AudioPlayer time_update)
  @impl true
  def handle_event(_event, _params, socket) do
    {:noreply, socket}
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
              source: "spotify",
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
     |> push_notification(:success, "Playlist Imported", msg)
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

    {:noreply,
     socket
     |> push_notification(:info, "Spotify Import", msg)
     |> assign(:fetching_spotify, false)
     |> put_flash(:info, msg)}
  end

  @impl true
  def handle_info({:spotify_metadata, _url, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> push_notification(:error, "Import Failed", "Spotify import failed: #{reason}")
     |> assign(:fetching_spotify, false)
     |> put_flash(:error, "Failed: #{reason}")}
  end

  # Handle lalal.ai modal key test result
  @impl true
  # Handle lalal.ai connection test result (system/resolved key)
  @impl true
  # Handle Task.Supervisor task failures (e.g., if spotdl process crashes)
  @impl true
  @impl true
  # Track-level pipeline progress (from workers)
  @impl true
  def handle_info({:pipeline_progress, %{track_id: track_id, stage: stage} = payload}, socket) do
    pipelines = socket.assigns.pipelines
    pipeline = Map.get(pipelines, track_id, %{})

    # Preserve job_id and engine from existing stage data (set when job was enqueued)
    # so the cancel button remains functional during live progress updates.
    existing_stage = Map.get(pipeline, stage, %{})

    stage_data =
      %{status: payload.status, progress: payload.progress}
      |> maybe_put(:job_id, Map.get(existing_stage, :job_id))
      |> maybe_put(:engine, Map.get(existing_stage, :engine))

    updated_pipeline = Map.put(pipeline, stage, stage_data)

    pipelines = Map.put(pipelines, track_id, updated_pipeline)

    socket =
      if payload.status == :failed do
        stage_name = stage |> to_string() |> String.capitalize()

        socket
        |> push_notification(:error, "#{stage_name} Failed", "#{stage_name} failed for track. Check server logs.", %{track_id: track_id})
        |> put_flash(:error, "#{stage_name} failed. Check server logs for details.")
      else
        socket
      end

    # When download or processing completes, update the track entry in the library stream
    socket =
      if payload.status == :completed && stage in [:download, :processing] do
        case Music.get_track(track_id) do
          {:ok, track} when not is_nil(track) -> stream_insert(socket, :tracks, track)
          _ -> socket
        end
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
        |> assign(:midi_result, Music.get_midi_result_for_track(track_id))
        |> assign(:chord_result, Music.get_chord_result_for_track(track_id))
      else
        socket
      end

    {:noreply, assign(socket, :pipelines, pipelines)}
  end

  # MIDI conversion complete - reload midi_result
  @impl true
  # Chord detection complete - reload chord_result
  @impl true
  # Pipeline complete - reload the track to get fresh data
  @impl true
  # Playlist-level pipeline update (from playlist_pipeline:{playlist_id} topic)
  @impl true
  def handle_info({:playlist_track_update, %{track_id: track_id, stage: stage, status: status, progress: progress}}, socket) do
    pipelines = socket.assigns.pipelines
    pipeline = Map.get(pipelines, track_id, %{})
    updated_pipeline = Map.put(pipeline, stage, %{status: status, progress: progress})
    {:noreply, assign(socket, :pipelines, Map.put(pipelines, track_id, updated_pipeline))}
  end

  @impl true
  # Notification forwarding to bell component
  @impl true
  def handle_info({:new_notification, _notification}, socket) do
    send_update(SoundForgeWeb.Live.Components.NotificationBell,
      id: "notification-bell",
      refresh: true
    )

    {:noreply, socket}
  end

  # Pipeline tracker "clear completed" forwarding
  @impl true
  def handle_info({:dismiss_pipeline_from_tracker, track_id}, socket) do
    pipelines = Map.delete(socket.assigns.pipelines, track_id)
    {:noreply, assign(socket, :pipelines, pipelines)}
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
  def handle_info({:initiate_spotify_play, uri}, socket) do
    handle_event("play_spotify", %{"uri" => uri}, socket)
  end

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

  @impl true
  @impl true
  # -- Auto Cue PubSub forwarding to DjTabComponent and ChromaticPadsComponent --

  @impl true
  # -- Chef PubSub forwarding to DjTabComponent --

  @impl true
  @impl true
  @impl true
  # -- MIDI handle_info callbacks --

  @impl true
  @impl true
  # Throttle BPM updates to 2 Hz max and only when value changes by ≥0.5 BPM.
  # MIDI clock (0xF8) fires at 24 PPQN — ~54 Hz at 134 BPM. Without throttling
  # this causes a LiveView diff on every tick even when the BPM reading is stable.
  # send_update to DjTabComponent is intentionally OMITTED here — every send_update
  # causes a component re-render diff even when assigns don't change, which floods
  # the WebSocket. MIDI sync pitch is handled by the component subscribing via
  # its own PubSub route (see dj_tab_component.ex subscribe_midi_clock/1).
  # BPM display in AppHeader updates at most once per 5s with ≥1 BPM change.
  # The else-branch does NOT assign last_bpm_ms — doing so causes a re-render on
  # every beat even when midi_bpm hasn't changed, flooding the WebSocket with
  # {10:, 17:} diffs at MIDI clock rate (~2 Hz). last_bpm_ms is only reset when
  # we actually update midi_bpm, effectively rate-limiting to 0.2 Hz.
  @bpm_update_interval_ms 5_000

  @impl true
  @impl true
  @impl true
  @impl true
  @impl true
  # Raw MIDI events from Dispatcher (when monitor is listening, Story v4.7.0)
  @impl true
  # Global MIDI bar control messages
  @impl true
  # GlobalBroadcaster events (on pages other than dashboard)

  @impl true
  def handle_info({:batch_progress, %{batch_job_id: _id, status: status, completed_count: completed, total_count: total}}, socket) do
    batch_status = socket.assigns.batch_status

    updated_status =
      if batch_status do
        %{batch_status | status: status, completed_count: completed, total_count: total}
      else
        batch_status
      end

    {:noreply, assign(socket, :batch_status, updated_status)}
  end

  @impl true
  def handle_info({:batch_complete, %{batch_job_id: _id, completed_count: completed, failed_count: failed, total_count: total}}, socket) do
    msg =
      if failed > 0 do
        "Batch complete: #{completed}/#{total} succeeded, #{failed} failed"
      else
        "Batch complete: #{completed} tracks processed successfully"
      end

    {:noreply,
     socket
     |> assign(:batch_processing, false)
     |> assign(:batch_mode, false)
     |> put_flash(:info, msg)}
  end

  # UAT scenario step execution via handle_info
  # Each step runs a check and advances to the next step or marks pass/fail

  # -- Template helpers --

  @pipeline_stages [:download, :processing, :analysis]

  def radar_features(analysis, chord_result \\ nil) do
    features = analysis.features || %{}

    base = %{
      tempo: analysis.tempo,
      energy: analysis.energy,
      spectral_centroid: analysis.spectral_centroid,
      spectral_rolloff: analysis.spectral_rolloff,
      zero_crossing_rate: analysis.zero_crossing_rate,
      spectral_bandwidth: get_in(features, ["spectral", "bandwidth_mean"]),
      spectral_flatness: get_in(features, ["spectral", "flatness_mean"])
    }

    # Add harmonic complexity from chord data if available
    if chord_result && is_list(chord_result.chords) && length(chord_result.chords) > 0 do
      # Harmonic complexity: unique chord count / total chords (higher = more complex)
      unique_chords = chord_result.chords |> Enum.map(& &1["chord"]) |> Enum.uniq() |> length()
      total_chords = length(chord_result.chords)
      complexity = unique_chords / max(total_chords, 1)
      Map.put(base, :harmonic_complexity, complexity)
    else
      base
    end
  end

  def beats_with_tempo(analysis) do
    features = analysis.features || %{}
    beats = features["beats"] || %{}

    if is_map(beats),
      do: Map.put(beats, "tempo", analysis.tempo),
      else: %{"tempo" => analysis.tempo}
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

  defp scope_user_id(%{user: %{id: id}}), do: id
  defp scope_user_id(_), do: nil

  # Reliable user_id resolution: scope first, then socket assigns fallback
  defp user_id(socket) do
    scope_user_id(socket.assigns[:current_scope]) || socket.assigns[:current_user_id]
  end

  # Puts a key/value into a map only when value is not nil.
  # Updates a single stage within the pipelines assigns using the given function.
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

  defp load_scope_from_session(session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _inserted_at} <- SoundForge.Accounts.get_user_by_session_token(token) do
      SoundForge.Accounts.Scope.for_user(user)
    else
      _ -> nil
    end
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

  defp valid_album_art?(nil), do: false
  defp valid_album_art?(""), do: false

  defp valid_album_art?(url) when is_binary(url) do
    not String.starts_with?(url, "https://mosaic.scdn.co/")
  end

  defp valid_album_art?(_), do: false

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
     |> assign(:select_all_pages, false)
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

  # Build a pipeline stage map from preloaded job associations on a Track struct.
  # Used to seed @pipelines when navigating to a playlist.
  # Auto-enqueue missing pipeline stages for tracks in a playlist.
  # Targets tracks that have a completed download but no completed analysis.
  defp spotify_linked?(nil), do: false

  defp spotify_linked?(user_id) do
    SoundForge.Spotify.OAuth.linked?(user_id)
  rescue
    _ -> false
  end

  # -- MIDI helpers --

  # Builds a raw MIDI event map for the floating monitor panel
  @note_names ~w(C C# D D# E F F# G G# A A# B)

  # -- DevTools helpers --

  # -- UAT helpers --

  @max_uat_log 100

  # Step executors return {status, detail_string}
  # Catch-all for undefined steps
  # -- Notification persistence helpers --

  # Persists a notification to the ETS-backed store so it appears in the
  # NotificationBell dropdown. This should be called for significant user-facing
  # events (pipeline completion, failures, imports, deletions) but NOT for
  # transient validation errors like "Track not found".
  defp push_notification(socket, type, title, message, metadata \\ %{}) do
    user_id = socket.assigns[:current_user_id]

    if user_id do
      Notifications.push(user_id, %{
        type: type,
        title: title,
        message: message,
        metadata: metadata
      })
    end

    socket
  end

  # Serialize NoteEdit structs to JS-friendly maps (onset_sec→onset, duration_sec→duration)
end
