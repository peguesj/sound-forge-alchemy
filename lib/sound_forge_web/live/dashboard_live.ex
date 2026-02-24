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

  @max_debug_logs 500
  @max_midi_log 50

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
      |> assign(:sort_by, :newest)
      |> assign(:view_mode, :grid)
      |> assign(:filters, %{status: "all", artist: "all"})
      |> assign(:artists, list_artists(scope))
      |> assign(:selected_ids, MapSet.new())
      |> assign(:select_all, false)
      |> assign(:batch_mode, false)
      |> assign(:batch_processing, false)
      |> assign(:batch_status, nil)
      |> assign(:show_batch_modal, false)
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
      |> assign(:selected_engine, "demucs")
      |> assign(:preview_mode, false)
      |> assign(:show_lalalai_modal, false)
      |> assign(:lalalai_modal_expanded, false)
      |> assign(:lalalai_modal_key_input, "")
      |> assign(:lalalai_modal_testing, false)
      |> assign(:lalalai_modal_test_result, nil)
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
      |> assign(:midi_transport, :stopped)
      |> assign(:midi_log, [])
      |> assign(:trace_jobs, [])
      |> assign(:trace_selected_job, nil)
      |> assign(:trace_timeline, [])
      |> assign(:trace_graph, %{nodes: [], links: []})
      |> assign(:worker_stats, [])
      |> assign(:queue_tab, :active)
      |> assign(:queue_active_jobs, [])
      |> assign(:queue_history_jobs, [])
      |> assign(:queue_history_has_more, false)
      |> assign(:daw_track_id, nil)
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

  def handle_params(%{"tab" => "dj"}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:live_action, :index)
     |> assign(:nav_tab, :dj)
     |> assign(:nav_context, :dj)}
  end

  def handle_params(%{"tab" => "daw", "track_id" => track_id}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:live_action, :index)
     |> assign(:nav_tab, :daw)
     |> assign(:nav_context, :daw)
     |> assign(:daw_track_id, track_id)}
  end

  def handle_params(%{"tab" => "daw"}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:live_action, :index)
     |> assign(:nav_tab, :daw)
     |> assign(:nav_context, :daw)
     |> assign(:daw_track_id, nil)}
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


  # -- Batch Mode (BatchProcessor integration) --

  @impl true
  def handle_event("toggle_batch_mode", _params, socket) do
    new_mode = !socket.assigns.batch_mode

    socket =
      socket
      |> assign(:batch_mode, new_mode)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:select_all, false)

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
       |> push_notification(:info, "Download Started", "Downloading \"#{track.title}\"...", %{track_id: track.id})
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

    engine = socket.assigns.selected_engine
    preview = socket.assigns.preview_mode

    lalalai_opts =
      if engine == "lalalai" do
        mode = socket.assigns.lalalai_mode

        base = [lalalai_mode: mode]

        case mode do
          "multistem" ->
            stems = socket.assigns.multistem_selection |> MapSet.to_list()
            base ++ [multistem_stems: stems]

          "voice_clean" ->
            base ++ [noise_level: socket.assigns.noise_level]

          "voice_change" ->
            base ++
              [
                voice_pack_id: socket.assigns.voice_pack_id,
                accent: socket.assigns.accent
              ]

          "demuser" ->
            base ++ [dereverb: socket.assigns.dereverb]

          _ ->
            base
        end
      else
        []
      end

    with {:ok, track} <- fetch_owned_track(socket, id),
         {:ok, job} <- start_processing(track.id, user_id, [engine: engine, preview: preview] ++ lalalai_opts) do
      maybe_subscribe(socket, track.id)

      pipelines = socket.assigns.pipelines
      pipeline = Map.get(pipelines, track.id, %{})
      updated_pipeline = Map.put(pipeline, :processing, %{status: :queued, progress: 0, job_id: job.id, engine: job.engine})
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
  def handle_event("select_engine", %{"engine" => "lalalai"}, socket) do
    user_id = socket.assigns[:current_user_id]

    if LalalAI.configured_for_user?(user_id) do
      {:noreply, assign(socket, :selected_engine, "lalalai")}
    else
      {:noreply,
       socket
       |> assign(:show_lalalai_modal, true)
       |> assign(:lalalai_modal_expanded, false)
       |> assign(:lalalai_modal_key_input, "")
       |> assign(:lalalai_modal_testing, false)
       |> assign(:lalalai_modal_test_result, nil)}
    end
  end

  def handle_event("select_engine", %{"engine" => "demucs"}, socket) do
    {:noreply, assign(socket, :selected_engine, "demucs")}
  end

  def handle_event("select_lalalai_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :lalalai_mode, mode)}
  end

  def handle_event("toggle_multistem", %{"stem" => stem}, socket) do
    selection = socket.assigns.multistem_selection

    updated =
      if MapSet.member?(selection, stem) do
        MapSet.delete(selection, stem)
      else
        MapSet.put(selection, stem)
      end

    {:noreply, assign(socket, :multistem_selection, updated)}
  end

  def handle_event("set_noise_level", %{"level" => level}, socket) do
    parsed = String.to_integer(level)
    {:noreply, assign(socket, :noise_level, parsed)}
  end

  def handle_event("select_voice_pack", %{"pack_id" => pack_id}, socket) do
    {:noreply, assign(socket, :voice_pack_id, pack_id)}
  end

  def handle_event("set_accent", %{"value" => value}, socket) do
    parsed = String.to_float(value)
    {:noreply, assign(socket, :accent, parsed)}
  end

  def handle_event("toggle_dereverb", _params, socket) do
    {:noreply, update(socket, :dereverb, &(!&1))}
  end

  def handle_event("close_lalalai_modal", _params, socket) do
    {:noreply, assign(socket, :show_lalalai_modal, false)}
  end

  def handle_event("expand_lalalai_key_form", _params, socket) do
    {:noreply, assign(socket, :lalalai_modal_expanded, true)}
  end

  def handle_event("lalalai_modal_key_input", %{"key" => key}, socket) do
    {:noreply, assign(socket, :lalalai_modal_key_input, key)}
  end

  def handle_event("test_save_lalalai_key", _params, socket) do
    key = socket.assigns.lalalai_modal_key_input

    if key == "" do
      {:noreply, assign(socket, :lalalai_modal_test_result, {:error, "Please enter an API key"})}
    else
      socket = assign(socket, :lalalai_modal_testing, true)
      lv_pid = self()

      Task.Supervisor.async_nolink(SoundForge.TaskSupervisor, fn ->
        result = LalalAI.test_api_key(key)
        send(lv_pid, {:lalalai_modal_test_result, result, key})
      end)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_lalalai_task", %{"job-id" => job_id}, socket) do
    job = Music.get_processing_job!(job_id)
    task_id = get_in(job.options || %{}, ["lalalai_task_id"])

    if task_id do
      case LalalAI.cancel_task([task_id]) do
        {:ok, _} ->
          Music.update_processing_job(job, %{status: :cancelled})
          SoundForge.Jobs.PipelineBroadcaster.broadcast_stage_failed(job.track_id, job_id, :processing)

          # Optimistically update the pipeline UI to show :cancelled immediately
          socket =
            update_pipeline_stage(socket, job.track_id, :processing, fn stage_data ->
              Map.merge(stage_data, %{status: :cancelled, progress: stage_data[:progress] || 0})
            end)

          {:noreply, put_flash(socket, :info, "Task cancelled")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to cancel: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "No task ID found")}
    end
  end

  @impl true
  def handle_event("cancel_all_lalalai_tasks", _params, socket) do
    case LalalAI.cancel_all_tasks() do
      {:ok, _} ->
        # Optimistically mark all in-progress lalalai processing stages as cancelled
        socket =
          Enum.reduce(socket.assigns.pipelines, socket, fn {track_id, pipeline}, acc ->
            case Map.get(pipeline, :processing) do
              %{status: s, engine: "lalalai"} when s in [:processing, :queued] ->
                update_pipeline_stage(acc, track_id, :processing, fn stage_data ->
                  Map.merge(stage_data, %{status: :cancelled, progress: stage_data[:progress] || 0})
                end)

              _ ->
                acc
            end
          end)

        {:noreply, put_flash(socket, :info, "All lalal.ai tasks cancelled")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel all: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("toggle_preview", _params, socket) do
    {:noreply, assign(socket, :preview_mode, !socket.assigns.preview_mode)}
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
  def handle_event("nav_tab", %{"tab" => "library"}, socket) do
    socket =
      socket
      |> assign(:nav_tab, :library)
      |> assign(:nav_context, :all_tracks)
      |> assign(:browse_filter, nil)
      |> assign(:page, 1)
      |> assign(:filters, %{status: "all", artist: "all"})
      |> assign(:selected_ids, MapSet.new())
      |> assign(:select_all, false)

    reload_tracks(socket, page: 1, filters: %{status: "all", artist: "all"})
  end

  def handle_event("nav_tab", %{"tab" => "browse"}, socket) do
    {:noreply,
     socket
     |> assign(:nav_tab, :browse)
     |> assign(:nav_context, :artist)
     |> assign(:browse_filter, nil)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_all, false)}
  end

  def handle_event("nav_tab", %{"tab" => "dj"}, socket) do
    {:noreply,
     socket
     |> assign(:nav_tab, :dj)
     |> assign(:nav_context, :dj)
     |> push_patch(to: ~p"/?#{[tab: "dj"]}")}
  end

  def handle_event("nav_tab", %{"tab" => "daw"}, socket) do
    {:noreply,
     socket
     |> assign(:nav_tab, :daw)
     |> assign(:nav_context, :daw)
     |> push_patch(to: ~p"/?#{[tab: "daw"]}")}
  end

  def handle_event("nav_tab", %{"tab" => _unknown}, socket) do
    {:noreply, socket}
  end

  # -- Keyboard delegation to DJ component --

  @impl true
  def handle_event("keydown", params, %{assigns: %{nav_tab: :dj}} = socket) do
    send_update(SoundForgeWeb.Live.Components.DjTabComponent,
      id: "dj-tab",
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

  # -- Debug Panel --

  @impl true
  def handle_event("toggle_debug_panel", _params, socket) do
    {:noreply, update(socket, :debug_panel_open, &(!&1))}
  end

  @impl true
  def handle_event("close_debug_panel", _params, socket) do
    {:noreply, assign(socket, :debug_panel_open, false)}
  end

  @valid_debug_tabs ~w(logs tracing midi)a

  @impl true
  def handle_event("debug_tab", %{"tab" => tab}, socket) do
    tab_atom =
      try do
        atom = String.to_existing_atom(tab)
        if atom in @valid_debug_tabs, do: atom, else: :logs
      rescue
        ArgumentError -> :logs
      end

    socket =
      if tab_atom == :tracing do
        jobs = SoundForge.Debug.Jobs.recent_jobs(50)
        assign(socket, :trace_jobs, jobs)
      else
        socket
      end

    {:noreply, assign(socket, :debug_tab, tab_atom)}
  end

  @impl true
  def handle_event("trace_select_job", %{"job-id" => job_id_str}, socket) do
    case Integer.parse(job_id_str) do
      {job_id, _} ->
        job = SoundForge.Debug.Jobs.get_job(job_id)

        if job do
          track_id = job.args["track_id"]
          pipeline_jobs = if track_id, do: SoundForge.Debug.Jobs.jobs_for_track(track_id), else: [job]
          timeline = SoundForge.Debug.Jobs.build_timeline(pipeline_jobs)
          graph = SoundForge.Debug.Jobs.build_graph(pipeline_jobs)

          {:noreply,
           socket
           |> assign(:trace_selected_job, job)
           |> assign(:trace_timeline, timeline)
           |> assign(:trace_graph, graph)
           |> push_event("job_trace_graph", graph)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("trace_refresh", _params, socket) do
    jobs = SoundForge.Debug.Jobs.recent_jobs(50)
    {:noreply, assign(socket, :trace_jobs, jobs)}
  end

  @impl true
  def handle_event("debug_log_filter", %{"level" => level}, socket) do
    {:noreply, assign(socket, :debug_log_filter_level, level)}
  end

  @impl true
  def handle_event("debug_log_filter_ns", %{"namespace" => ns}, socket) do
    {:noreply, assign(socket, :debug_log_filter_ns, ns)}
  end

  @impl true
  def handle_event("debug_log_search", %{"search" => search}, socket) do
    {:noreply, assign(socket, :debug_log_search, search)}
  end

  @impl true
  def handle_event("clear_debug_logs", _params, socket) do
    {:noreply, assign(socket, :debug_logs, [])}
  end

  @impl true
  def handle_event("clear_midi_log", _params, socket) do
    {:noreply, assign(socket, :midi_log, [])}
  end

  @impl true
  def handle_event("toggle_debug_workers", _params, socket) do
    opening = !socket.assigns.debug_workers_open

    socket =
      if opening do
        assign(socket, :worker_stats, SoundForge.Debug.Jobs.worker_stats())
      else
        socket
      end

    {:noreply, assign(socket, :debug_workers_open, opening)}
  end

  @impl true
  def handle_event("filter_logs_by_worker", %{"worker" => worker_name}, socket) do
    namespace = "oban.#{worker_name}"

    {:noreply,
     socket
     |> assign(:debug_tab, :logs)
     |> assign(:debug_log_filter_ns, namespace)}
  end

  @impl true
  def handle_event("toggle_debug_queue", _params, socket) do
    {:noreply, update(socket, :debug_queue_open, &(!&1))}
  end

  @impl true
  def handle_event("queue_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :queue_tab, String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("queue_refresh_history", _params, socket) do
    {:noreply, load_queue_history(socket)}
  end

  @impl true
  def handle_event("queue_load_more", _params, socket) do
    case List.last(socket.assigns.queue_history_jobs) do
      nil ->
        {:noreply, socket}

      last_job ->
        {more_jobs, has_more} =
          SoundForge.Debug.Jobs.history_jobs(before_id: last_job.id)

        {:noreply,
         socket
         |> assign(:queue_history_jobs, socket.assigns.queue_history_jobs ++ more_jobs)
         |> assign(:queue_history_has_more, has_more)}
    end
  end

  @impl true
  def handle_event("anchor_job_logs", %{"job-id" => job_id_str}, socket) do
    {:noreply,
     socket
     |> assign(:debug_tab, :logs)
     |> assign(:debug_log_filter_level, "all")
     |> assign(:debug_log_filter_ns, "all")
     |> assign(:debug_log_search, job_id_str)}
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
           {:ok, result} <- retry_pipeline_stage(track.id, stage_atom, user_id) do
        pipelines = socket.assigns.pipelines
        pipeline = Map.get(pipelines, track_id, %{})

        stage_data =
          if stage_atom == :processing and is_struct(result, SoundForge.Music.ProcessingJob) do
            %{status: :queued, progress: 0, job_id: result.id, engine: result.engine}
          else
            %{status: :queued, progress: 0}
          end

        updated_pipeline = Map.put(pipeline, stage_atom, stage_data)
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
  def handle_info({:lalalai_modal_test_result, result, key}, socket) do
    case result do
      {:ok, :valid} ->
        user_id = socket.assigns[:current_user_id]

        if user_id do
          Settings.save_lalalai_api_key(user_id, key)
        end

        {:noreply,
         socket
         |> assign(:lalalai_modal_testing, false)
         |> assign(:lalalai_modal_test_result, {:ok, "API key verified and saved."})
         |> assign(:selected_engine, "lalalai")
         |> assign(:show_lalalai_modal, false)
         |> put_flash(:info, "lalal.ai API key saved. Cloud separation is now available.")}

      {:error, :invalid_api_key} ->
        {:noreply,
         socket
         |> assign(:lalalai_modal_testing, false)
         |> assign(:lalalai_modal_test_result, {:error, "Invalid API key. Please check and try again."})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:lalalai_modal_testing, false)
         |> assign(:lalalai_modal_test_result, {:error, "Test failed: #{inspect(reason)}"})}
    end
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
      Enum.reduce([:download, :processing, :analysis], pipeline, fn stage, acc ->
        if Map.has_key?(acc, stage) do
          Map.put(acc, stage, %{status: :completed, progress: 100})
        else
          acc
        end
      end)

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

    # Resolve track title for the notification if possible
    track_title =
      case Music.get_track(track_id) do
        {:ok, t} when not is_nil(t) -> t.title
        _ -> "Track"
      end

    {:noreply,
     socket
     |> push_notification(:success, "Pipeline Complete", "\"#{track_title}\" is ready.", %{track_id: track_id})
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
  def handle_info({:debug_log, event}, socket) do
    logs = [event | socket.assigns.debug_logs] |> Enum.take(@max_debug_logs)

    namespaces =
      if event.namespace do
        MapSet.put(socket.assigns.debug_log_namespaces, event.namespace)
      else
        socket.assigns.debug_log_namespaces
      end

    {:noreply,
     socket
     |> assign(:debug_logs, logs)
     |> assign(:debug_log_namespaces, namespaces)}
  end

  @impl true
  def handle_info({:worker_status_change, _payload}, socket) do
    {:noreply,
     socket
     |> assign(:worker_stats, SoundForge.Debug.Jobs.worker_stats())
     |> assign(:queue_active_jobs, SoundForge.Debug.Jobs.active_jobs())}
  end

  # -- MIDI handle_info callbacks --

  @impl true
  def handle_info({:midi_device_connected, device}, socket) do
    devices = safe_list_midi_devices()
    log_entry = midi_log_entry("Device connected: #{device.name}")

    {:noreply,
     socket
     |> assign(:midi_devices, devices)
     |> append_midi_log(log_entry)}
  end

  @impl true
  def handle_info({:midi_device_disconnected, device}, socket) do
    devices = safe_list_midi_devices()
    log_entry = midi_log_entry("Device disconnected: #{device.name}")

    {:noreply,
     socket
     |> assign(:midi_devices, devices)
     |> append_midi_log(log_entry)}
  end

  @impl true
  def handle_info({:bpm_update, bpm} = msg, socket) do
    socket = assign(socket, :midi_bpm, bpm)

    socket =
      if socket.assigns.nav_tab == :dj do
        send_update(SoundForgeWeb.Live.Components.DjTabComponent,
          id: "dj-tab",
          midi_event: msg
        )

        socket
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:transport, state} = msg, socket) do
    log_entry = midi_log_entry("Transport: #{state}")

    socket =
      socket
      |> assign(:midi_transport, state)
      |> append_midi_log(log_entry)

    if socket.assigns.nav_tab == :dj do
      send_update(SoundForgeWeb.Live.Components.DjTabComponent,
        id: "dj-tab",
        midi_event: msg
      )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:midi_action, :stem_volume, %{volume: volume, target: target} = params}, socket) do
    log_entry = midi_log_entry("CC -> stem_volume target=#{target} vol=#{Float.round(volume, 2)}")

    socket =
      socket
      |> push_event("midi_fader_update", %{target: target, volume: volume, track_id: Map.get(params, :track_id)})
      |> append_midi_log(log_entry)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:midi_action, action, params}, socket) do
    log_entry = midi_log_entry("#{action}: #{inspect(params, limit: 3)}")
    {:noreply, append_midi_log(socket, log_entry)}
  end


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

  # -- Template helpers --

  def filtered_debug_logs(logs, level_filter, ns_filter, search) do
    logs
    |> Enum.filter(fn log ->
      (level_filter == "all" or to_string(log.level) == level_filter) and
        (ns_filter == "all" or log.namespace == ns_filter) and
        (search == "" or String.contains?(String.downcase(log.message), String.downcase(search)))
    end)
    |> Enum.reverse()
  end

  def log_level_color(:debug), do: "text-gray-500"
  def log_level_color(:info), do: "text-blue-400"
  def log_level_color(:warning), do: "text-amber-400"
  def log_level_color(:warn), do: "text-amber-400"
  def log_level_color(:error), do: "text-red-400"
  def log_level_color(_), do: "text-gray-400"

  def log_level_badge_class(:debug), do: "bg-gray-700 text-gray-300"
  def log_level_badge_class(:info), do: "bg-blue-900/50 text-blue-300"
  def log_level_badge_class(:warning), do: "bg-amber-900/50 text-amber-300"
  def log_level_badge_class(:warn), do: "bg-amber-900/50 text-amber-300"
  def log_level_badge_class(:error), do: "bg-red-900/50 text-red-300"
  def log_level_badge_class(_), do: "bg-gray-700 text-gray-300"

  def log_line_border(:error), do: "border-l-2 border-red-500"
  def log_line_border(_), do: ""

  def worker_status_class(:active), do: "bg-green-500 animate-pulse"
  def worker_status_class(:errored), do: "bg-red-500"
  def worker_status_class(_), do: "bg-gray-500"

  def duration_since(nil, _), do: "?"
  def duration_since(_, nil), do: "?"

  def duration_since(%DateTime{} = from, %DateTime{} = to) do
    diff_ms = DateTime.diff(to, from, :millisecond)
    format_duration_ms(diff_ms)
  end

  def duration_since(%NaiveDateTime{} = from, %NaiveDateTime{} = to) do
    diff_ms = NaiveDateTime.diff(to, from, :millisecond)
    format_duration_ms(diff_ms)
  end

  def duration_since(_, _), do: "?"

  defp format_duration_ms(ms) when ms < 1_000, do: "#{ms}ms"
  defp format_duration_ms(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)}s"
  defp format_duration_ms(ms), do: "#{Float.round(ms / 60_000, 1)}m"

  def format_job_time(nil), do: "-"
  def format_job_time(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  def format_job_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  def format_job_time(_), do: "-"

  def job_state_badge_class("completed"), do: "bg-green-900/50 text-green-300"
  def job_state_badge_class("executing"), do: "bg-blue-900/50 text-blue-300"
  def job_state_badge_class("available"), do: "bg-gray-700 text-gray-300"
  def job_state_badge_class("scheduled"), do: "bg-gray-700 text-gray-300"
  def job_state_badge_class("retryable"), do: "bg-amber-900/50 text-amber-300"
  def job_state_badge_class("discarded"), do: "bg-red-900/50 text-red-300"
  def job_state_badge_class("cancelled"), do: "bg-red-900/50 text-red-300"
  def job_state_badge_class(_), do: "bg-gray-700 text-gray-300"

  def short_worker(full_worker) when is_binary(full_worker) do
    full_worker |> String.split(".") |> List.last() |> String.replace("Worker", "")
  end

  def short_worker(_), do: "?"

  def job_args_summary(args) when is_map(args) do
    cond do
      args["track_title"] -> String.slice(args["track_title"], 0, 30)
      args["track_id"] -> "Track #{String.slice(args["track_id"], 0, 8)}.."
      true -> "-"
    end
  end

  def job_args_summary(_), do: "-"

  def job_duration(job) do
    case {job.attempted_at, job.completed_at} do
      {%DateTime{} = start, %DateTime{} = finish} ->
        diff = DateTime.diff(finish, start, :millisecond)
        format_duration_ms(diff)

      {%NaiveDateTime{} = start, %NaiveDateTime{} = finish} ->
        diff = NaiveDateTime.diff(finish, start, :millisecond)
        format_duration_ms(diff)

      _ ->
        "-"
    end
  end

  def pipeline_track_title(_streams, _track_id), do: "Track"

  @pipeline_stages [:download, :processing, :analysis]

  def pipeline_complete?(pipeline) do
    triggered = Enum.filter(@pipeline_stages, &Map.has_key?(pipeline, &1))

    triggered != [] and
      Enum.all?(triggered, fn stage ->
        match?(%{status: :completed}, Map.get(pipeline, stage))
      end)
  end

  def radar_features(analysis) do
    features = analysis.features || %{}

    %{
      tempo: analysis.tempo,
      energy: analysis.energy,
      spectral_centroid: analysis.spectral_centroid,
      spectral_rolloff: analysis.spectral_rolloff,
      zero_crossing_rate: analysis.zero_crossing_rate,
      spectral_bandwidth: get_in(features, ["spectral", "bandwidth_mean"]),
      spectral_flatness: get_in(features, ["spectral", "flatness_mean"])
    }
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

  defp load_queue_history(socket) do
    {jobs, has_more} = SoundForge.Debug.Jobs.history_jobs()
    socket |> assign(:queue_history_jobs, jobs) |> assign(:queue_history_has_more, has_more)
  end
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

  # Puts a key/value into a map only when value is not nil.
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Updates a single stage within the pipelines assigns using the given function.
  defp update_pipeline_stage(socket, track_id, stage, fun) do
    pipelines = socket.assigns.pipelines
    pipeline = Map.get(pipelines, track_id, %{})
    stage_data = Map.get(pipeline, stage, %{})
    updated_pipeline = Map.put(pipeline, stage, fun.(stage_data))
    assign(socket, :pipelines, Map.put(pipelines, track_id, updated_pipeline))
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
    start_processing(track_id, user_id, [])
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

  defp start_processing(track_id, user_id, opts) do
    engine = Keyword.get(opts, :engine, "demucs")
    preview = Keyword.get(opts, :preview, false)
    model = Settings.get(user_id, :demucs_model)

    # lalal.ai mode-specific opts
    lalalai_mode = Keyword.get(opts, :lalalai_mode, "stem_separator")
    multistem_stems = Keyword.get(opts, :multistem_stems, [])
    noise_level = Keyword.get(opts, :noise_level, 0)
    voice_pack_id = Keyword.get(opts, :voice_pack_id, nil)
    accent = Keyword.get(opts, :accent, 0.5)
    dereverb = Keyword.get(opts, :dereverb, false)

    with {:ok, file_path} <- Music.get_download_path(track_id),
         {:ok, job} <-
           Music.create_processing_job(%{track_id: track_id, model: model, status: :queued, engine: engine, preview: preview}),
         {:ok, _oban_job} <-
           (%{
              "track_id" => track_id,
              "job_id" => job.id,
              "file_path" => file_path,
              "model" => model,
              "engine" => engine,
              "preview" => preview,
              "lalalai_mode" => lalalai_mode,
              "multistem_stems" => multistem_stems,
              "noise_level" => noise_level,
              "voice_pack_id" => voice_pack_id,
              "accent" => accent,
              "dereverb" => dereverb
            }
            |> SoundForge.Jobs.ProcessingWorker.new()
            |> Oban.insert()) do
      {:ok, job}
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

  # -- MIDI helpers --

  defp safe_list_midi_devices do
    SoundForge.MIDI.DeviceManager.list_devices()
  catch
    :exit, _ -> []
  end

  defp safe_get_midi_bpm do
    SoundForge.MIDI.Clock.get_bpm()
  catch
    :exit, _ -> nil
  end

  defp safe_get_midi_transport do
    SoundForge.MIDI.Clock.get_transport_state()
  catch
    :exit, _ -> :stopped
  end

  defp midi_log_entry(message) do
    %{
      id: System.unique_integer([:positive]),
      message: message,
      timestamp: DateTime.utc_now()
    }
  end

  defp append_midi_log(socket, entry) do
    logs = [entry | socket.assigns.midi_log] |> Enum.take(@max_midi_log)
    assign(socket, :midi_log, logs)
  end

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
end
