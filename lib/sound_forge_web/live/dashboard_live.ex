defmodule SoundForgeWeb.DashboardLive do
  use SoundForgeWeb, :live_view

  alias SoundForge.Music

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns[:current_scope]

    socket =
      socket
      |> assign(:page_title, "Sound Forge Alchemy")
      |> assign(:search_query, "")
      |> assign(:spotify_url, "")
      |> assign(:active_jobs, %{})
      |> assign(:pipelines, %{})
      |> assign(:track_count, count_tracks(scope))
      |> assign(:track, nil)
      |> assign(:stems, [])
      |> assign(:analysis, nil)
      |> assign(:sort_by, :newest)
      |> assign(:page, 1)
      |> assign(:per_page, per_page())
      |> allow_upload(:audio,
        accept: ~w(.mp3 .wav .flac .ogg .m4a .aac .wma),
        max_entries: 5,
        max_file_size: Application.get_env(:sound_forge, :max_upload_size, 100_000_000)
      )
      |> stream(:tracks, list_tracks(scope, page: 1, per_page: per_page()))

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

  @valid_sort_fields ~w(newest oldest title artist)a

  @impl true
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    sort_atom =
      try do
        atom = String.to_existing_atom(sort_by)
        if atom in @valid_sort_fields, do: atom, else: :newest
      rescue
        ArgumentError -> :newest
      end

    scope = socket.assigns[:current_scope]
    per_page = socket.assigns.per_page
    tracks = list_tracks(scope, sort_by: sort_atom, page: 1, per_page: per_page)

    {:noreply,
     socket
     |> assign(:sort_by, sort_atom)
     |> assign(:page, 1)
     |> stream(:tracks, tracks, reset: true)}
  end

  @impl true
  def handle_event("page", %{"page" => page_str}, socket) do
    page =
      case Integer.parse(page_str) do
        {n, _} when n > 0 -> n
        _ -> 1
      end

    scope = socket.assigns[:current_scope]
    per_page = socket.assigns.per_page
    sort_by = socket.assigns.sort_by
    tracks = list_tracks(scope, sort_by: sort_by, page: page, per_page: per_page)

    {:noreply,
     socket
     |> assign(:page, page)
     |> stream(:tracks, tracks, reset: true)}
  end

  @impl true
  def handle_event("fetch_spotify", %{"url" => url}, socket) do
    scope = socket.assigns[:current_scope]

    case SoundForge.Audio.SpotDL.fetch_metadata(url) do
      {:ok, tracks_data} ->
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
  def handle_event("upload_audio", _params, socket) do
    scope = socket.assigns[:current_scope]

    uploaded_tracks =
      consume_uploaded_entries(socket, :audio, fn %{path: tmp_path}, entry ->
        # Derive track title from filename
        filename = entry.client_name
        title = filename |> Path.rootname() |> String.replace(~r/[-_]+/, " ") |> String.trim()
        ext = Path.extname(filename)

        # Store the file
        SoundForge.Storage.ensure_directories!()
        dest_filename = "#{Ecto.UUID.generate()}#{ext}"
        dest_path = Path.join(SoundForge.Storage.downloads_path(), dest_filename)
        File.cp!(tmp_path, dest_path)

        # Create the track
        user_id =
          case scope do
            %{user: %{id: id}} -> id
            _ -> nil
          end

        case Music.create_track(%{
               title: title,
               user_id: user_id
             }) do
          {:ok, track} ->
            # Create download job record pointing to the uploaded file
            {:ok, _job} =
              Music.create_download_job(%{
                track_id: track.id,
                status: :completed,
                output_path: dest_path,
                file_size: entry.client_size
              })

            # Kick off processing pipeline (skip download, go straight to processing)
            model = Application.get_env(:sound_forge, :default_demucs_model, "htdemucs")

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

            {:ok, track}

          error ->
            File.rm(dest_path)
            error
        end
      end)

    successful = Enum.filter(uploaded_tracks, &match?({:ok, _}, &1))

    socket =
      Enum.reduce(successful, socket, fn {:ok, track}, acc ->
        if connected?(acc) do
          Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")
        end

        pipeline = %{
          track_id: track.id,
          download: %{status: :completed, progress: 100},
          processing: %{status: :queued, progress: 0}
        }

        pipelines = Map.put(acc.assigns.pipelines, track.id, pipeline)

        acc
        |> assign(:pipelines, pipelines)
        |> stream_insert(:tracks, track, at: 0)
        |> update(:track_count, &(&1 + 1))
      end)

    count = length(successful)

    msg =
      case count do
        0 -> nil
        1 -> "Uploaded 1 file, processing started"
        n -> "Uploaded #{n} files, processing started"
      end

    socket = if msg, do: put_flash(socket, :info, msg), else: socket
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
      case retry_pipeline_stage(track_id, stage_atom) do
        {:ok, _} ->
          pipelines = socket.assigns.pipelines
          pipeline = Map.get(pipelines, track_id, %{})
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
  end

  # Track-level pipeline progress (from workers)
  @impl true
  def handle_info({:pipeline_progress, %{track_id: track_id, stage: stage} = payload}, socket) do
    pipelines = socket.assigns.pipelines
    pipeline = Map.get(pipelines, track_id, %{})

    updated_pipeline =
      Map.put(pipeline, stage, %{status: payload.status, progress: payload.progress})

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
  def upload_error_to_string(:too_large), do: "File too large (max 100 MB)"
  def upload_error_to_string(:not_accepted), do: "Invalid file type"
  def upload_error_to_string(:too_many_files), do: "Too many files (max 5)"
  def upload_error_to_string(err), do: inspect(err)

  # -- Private helpers --

  defp start_single_pipeline(track_meta, original_url, scope) do
    # spotdl uses "song_id" for the Spotify track ID
    spotify_id = track_meta["song_id"] || track_meta["id"]
    spotify_url = track_meta["url"] || original_url

    with :ok <- check_duplicate(spotify_id, scope),
         {:ok, track} <- create_track_from_metadata(track_meta, spotify_url, scope),
         {:ok, download_job} <- Music.create_download_job(%{track_id: track.id, status: :queued}) do
      %{
        "track_id" => track.id,
        "spotify_url" => spotify_url,
        "quality" => Application.get_env(:sound_forge, :download_quality, "320k"),
        "job_id" => download_job.id
      }
      |> SoundForge.Jobs.DownloadWorker.new()
      |> Oban.insert()

      pipeline = %{track_id: track.id, download: %{status: :queued, progress: 0}}
      {:ok, track, pipeline}
    end
  end

  defp check_duplicate(nil, _scope), do: :ok

  defp check_duplicate(spotify_id, _scope) do
    case Music.get_track_by_spotify_id(spotify_id) do
      nil -> :ok
      _track -> {:error, :duplicate}
    end
  end

  defp create_track_from_metadata(metadata, spotify_url, scope) do
    user_id =
      case scope do
        %{user: %{id: id}} -> id
        _ -> nil
      end

    # spotdl metadata format:
    #   name, artists (list of strings), album_name, album_artist,
    #   song_id, duration (seconds), cover_url, url
    attrs = %{
      title: metadata["name"] || "Unknown",
      artist: extract_artist(metadata),
      album: metadata["album_name"] || metadata["album"],
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

  defp search_tracks(query, scope)
       when byte_size(query) > 0 and is_map(scope) and not is_nil(scope) do
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

  def pagination_range(_current_page, total) when total <= 7, do: 1..total |> Enum.to_list()

  def pagination_range(current_page, total) do
    start_page = max(1, current_page - 2)
    end_page = min(total, start_page + 4)
    start_page = max(1, end_page - 4)
    Enum.to_list(start_page..end_page)
  end

  defp count_tracks(scope) when is_map(scope) and not is_nil(scope) do
    try do
      Music.count_tracks(scope)
    rescue
      _ -> 0
    end
  end

  defp count_tracks(_scope) do
    try do
      Music.count_tracks()
    rescue
      _ -> 0
    end
  end

  defp per_page, do: Application.get_env(:sound_forge, :tracks_per_page, 24)

  defp total_pages(track_count, per_page) when per_page > 0 do
    max(1, ceil(track_count / per_page))
  end

  defp total_pages(_, _), do: 1

  defp retry_pipeline_stage(track_id, :download) do
    track = Music.get_track!(track_id)

    with {:ok, job} <- Music.create_download_job(%{track_id: track_id, status: :queued}) do
      %{
        "track_id" => track_id,
        "spotify_url" => track.spotify_url,
        "quality" => Application.get_env(:sound_forge, :download_quality, "320k"),
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

    with {:ok, job} <-
           Music.create_processing_job(%{track_id: track_id, model: model, status: :queued}) do
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
        "features" =>
          Application.get_env(:sound_forge, :analysis_features, [
            "tempo",
            "key",
            "energy",
            "spectral"
          ])
      }
      |> SoundForge.Jobs.AnalysisWorker.new()
      |> Oban.insert()
    end
  end
end
