defmodule SoundForgeWeb.Live.CrateDiggerLive do
  @moduledoc """
  CrateDigger — learning-focused Spotify playlist player for producers.

  Left panel: crate list + import form.
  Center panel: track list with stem config toggles.
  Right panel: slide-out inspector with WhoSampled, Track Details, Lyrics, Analysis,
               and per-track stem override.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Accounts
  alias SoundForge.CrateDigger
  alias SoundForge.CrateDigger.WhoSampledScraper
  alias SoundForge.Jobs.AnalysisWorker
  alias SoundForge.Jobs.DownloadWorker
  alias SoundForge.Music
  alias SoundForge.Repo

  require Logger

  @impl true
  def mount(_params, session, socket) do
    user = resolve_user(socket.assigns[:current_user], session)

    crates = if user, do: CrateDigger.list_crates(user.id), else: []

    socket =
      socket
      |> assign(:page_title, "Crate Digger — SFA")
      |> assign(:current_user, user)
      |> assign(:crates, crates)
      |> assign(:active_crate, List.first(crates))
      |> assign(:playlist_url, "")
      |> assign(:playlist_loading, false)
      |> assign(:playlist_error, nil)
      |> assign(:inspector_track, nil)
      |> assign(:inspector_open, false)
      # WhoSampled state per inspector_track
      |> assign(:whosampled_loading, false)
      |> assign(:whosampled_samples, nil)
      |> assign(:whosampled_error, nil)
      # Accordion section open/closed
      |> assign(:section_open, %{whosampled: false, details: false, lyrics: false, analysis: false, stems: false})
      # Analysis for active inspector track
      |> assign(:inspector_analysis, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — playlist import
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("update_playlist_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, :playlist_url, url)}
  end

  def handle_event("import_playlist", _params, socket) do
    url = String.trim(socket.assigns.playlist_url)
    user = socket.assigns.current_user

    if url == "" or is_nil(user) do
      {:noreply, assign(socket, :playlist_error, "Enter a Spotify playlist URL")}
    else
      socket = socket |> assign(:playlist_loading, true) |> assign(:playlist_error, nil)
      send(self(), {:load_playlist, url, user.id})
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — crate selection
  # ---------------------------------------------------------------------------

  def handle_event("select_crate", %{"id" => id}, socket) do
    crate = CrateDigger.get_crate(id)
    socket = socket |> assign(:active_crate, crate) |> assign(:inspector_track, nil) |> assign(:inspector_open, false)
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — inspector
  # ---------------------------------------------------------------------------

  def handle_event("open_inspector", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    tracks = active_tracks(socket)
    track = Enum.at(tracks, idx)

    analysis = if track, do: load_analysis(track["spotify_id"]), else: nil

    socket =
      socket
      |> assign(:inspector_track, track)
      |> assign(:inspector_open, true)
      |> assign(:inspector_analysis, analysis)
      |> assign(:whosampled_samples, nil)
      |> assign(:whosampled_loading, false)
      |> assign(:whosampled_error, nil)
      |> assign(:section_open, %{whosampled: false, details: false, lyrics: false, analysis: false, stems: false})

    {:noreply, socket}
  end

  def handle_event("close_inspector", _params, socket) do
    {:noreply, socket |> assign(:inspector_open, false) |> assign(:inspector_track, nil)}
  end

  # ---------------------------------------------------------------------------
  # Events — accordion sections
  # ---------------------------------------------------------------------------

  def handle_event("toggle_section", %{"section" => section_str}, socket) do
    section = String.to_existing_atom(section_str)
    current = socket.assigns.section_open
    updated = Map.update!(current, section, &(!&1))

    socket = assign(socket, :section_open, updated)

    # Lazy-load WhoSampled on first open
    socket =
      if section == :whosampled and updated.whosampled and
           is_nil(socket.assigns.whosampled_samples) and
           not socket.assigns.whosampled_loading do
        track = socket.assigns.inspector_track

        if track do
          send(self(), {:fetch_whosampled, track["spotify_id"], track["artist"], track["title"]})
          assign(socket, :whosampled_loading, true)
        else
          socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — stem config (playlist-level)
  # ---------------------------------------------------------------------------

  def handle_event("toggle_stem", %{"stem" => stem}, socket) do
    crate = socket.assigns.active_crate

    if crate do
      current_stems = crate.stem_config["enabled_stems"] || ["vocals", "drums", "bass", "other"]

      new_stems =
        if stem in current_stems do
          List.delete(current_stems, stem)
        else
          [stem | current_stems]
        end

      # Ensure at least one stem active
      new_stems = if Enum.empty?(new_stems), do: current_stems, else: new_stems

      case CrateDigger.update_crate_stem_config(crate, new_stems) do
        {:ok, updated_crate} ->
          crates = reload_crates(socket)
          {:noreply, socket |> assign(:active_crate, updated_crate) |> assign(:crates, crates)}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — per-track stem override
  # ---------------------------------------------------------------------------

  def handle_event("toggle_track_stem", %{"stem" => stem}, socket) do
    crate = socket.assigns.active_crate
    track = socket.assigns.inspector_track

    if crate && track do
      current_override = get_track_override(crate, track["spotify_id"])

      effective =
        current_override ||
          crate.stem_config["enabled_stems"] ||
          ["vocals", "drums", "bass", "other"]

      new_stems =
        if stem in effective do
          List.delete(effective, stem)
        else
          [stem | effective]
        end

      new_stems = if Enum.empty?(new_stems), do: effective, else: new_stems

      CrateDigger.set_track_stem_override(crate.id, track["spotify_id"], new_stems)
      updated_crate = CrateDigger.get_crate(crate.id)
      {:noreply, assign(socket, :active_crate, updated_crate)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_track_override", _params, socket) do
    crate = socket.assigns.active_crate
    track = socket.assigns.inspector_track

    if crate && track do
      CrateDigger.set_track_stem_override(crate.id, track["spotify_id"], nil)
      updated_crate = CrateDigger.get_crate(crate.id)
      {:noreply, assign(socket, :active_crate, updated_crate)}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — Load into SFA (enqueue download)
  # ---------------------------------------------------------------------------

  def handle_event("load_into_sfa", %{"spotify_url" => spotify_url}, socket) do
    user = socket.assigns.current_user

    if user && spotify_url && spotify_url != "" do
      # Build a minimal track record stub and enqueue
      %{
        "spotify_url" => spotify_url,
        "user_id" => user.id,
        "quality" => "320k",
        "job_id" => "crate-#{System.unique_integer([:positive])}"
      }
      |> DownloadWorker.new()
      |> Oban.insert()
    end

    {:noreply, put_flash(socket, :info, "Track queued for download.")}
  end

  # ---------------------------------------------------------------------------
  # Events — trigger analysis
  # ---------------------------------------------------------------------------

  def handle_event("trigger_analysis", %{"track_id" => track_id}, socket) do
    %{"track_id" => track_id}
    |> AnalysisWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Analysis queued.")}
  end

  # ---------------------------------------------------------------------------
  # Info handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:load_playlist, url, user_id}, socket) do
    case CrateDigger.load_spotify_playlist(user_id, url) do
      {:ok, crate} ->
        crates = CrateDigger.list_crates(user_id)

        socket =
          socket
          |> assign(:crates, crates)
          |> assign(:active_crate, CrateDigger.get_crate(crate.id))
          |> assign(:playlist_loading, false)
          |> assign(:playlist_url, "")

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:playlist_loading, false)
          |> assign(:playlist_error, "Failed to load playlist: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  def handle_info({:fetch_whosampled, spotify_id, artist, title}, socket) do
    case WhoSampledScraper.fetch_samples(spotify_id, artist, title) do
      {:ok, samples} ->
        socket =
          socket
          |> assign(:whosampled_loading, false)
          |> assign(:whosampled_samples, samples)
          |> assign(:whosampled_error, nil)

        {:noreply, socket}

      {:error, :rate_limited} ->
        socket =
          socket
          |> assign(:whosampled_loading, false)
          |> assign(:whosampled_error, :rate_limited)

        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("WhoSampled fetch failed: #{inspect(reason)}")

        socket =
          socket
          |> assign(:whosampled_loading, false)
          |> assign(:whosampled_error, :fetch_error)

        {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-gray-950 text-gray-100 overflow-hidden">
      <!-- Header -->
      <header class="flex items-center gap-4 px-6 py-3 border-b border-gray-800 bg-gray-900/80 shrink-0">
        <.link navigate={~p"/"} class="text-gray-500 hover:text-white transition-colors">
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
        </.link>
        <div class="flex items-center gap-2">
          <%= vinyl_icon() %>
          <h1 class="text-base font-semibold text-white">Crate Digger</h1>
        </div>
        <span class="text-xs text-gray-600">Learning-focused playlist player</span>
      </header>

      <!-- Main layout -->
      <div class="flex flex-1 overflow-hidden relative">
        <!-- Left panel: crate list + import -->
        <aside class="w-64 shrink-0 bg-gray-900 border-r border-gray-800 flex flex-col overflow-hidden">
          <div class="px-4 pt-4 pb-3 border-b border-gray-800 shrink-0">
            <h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Import Playlist</h2>
            <form phx-submit="import_playlist" phx-change="update_playlist_url" class="space-y-2">
              <input
                type="text"
                name="url"
                value={@playlist_url}
                placeholder="Spotify playlist URL"
                class="w-full px-3 py-1.5 text-xs bg-gray-800 border border-gray-700 rounded text-gray-200 placeholder-gray-600 focus:outline-none focus:border-purple-500"
                disabled={@playlist_loading}
              />
              <button
                type="submit"
                class="w-full px-3 py-1.5 text-xs font-medium bg-purple-600 hover:bg-purple-500 rounded text-white transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                disabled={@playlist_loading or @playlist_url == ""}
              >
                <%= if @playlist_loading, do: "Loading...", else: "Import" %>
              </button>
            </form>
            <p :if={@playlist_error} class="mt-2 text-xs text-red-400">{@playlist_error}</p>
          </div>

          <!-- Crate list -->
          <div class="flex-1 overflow-y-auto py-2">
            <!-- Empty state -->
            <div :if={@crates == []} class="px-4 py-8 text-center">
              <%= vinyl_icon_lg() %>
              <p class="mt-3 text-xs text-gray-500">Import a Spotify playlist to start digging</p>
            </div>

            <ul class="space-y-0.5 px-2">
              <li :for={crate <- @crates}>
                <button
                  phx-click="select_crate"
                  phx-value-id={crate.id}
                  class={[
                    "w-full flex items-start gap-2 px-3 py-2 rounded text-left transition-colors text-xs",
                    if(@active_crate && @active_crate.id == crate.id,
                      do: "bg-purple-600/20 text-purple-300",
                      else: "text-gray-400 hover:bg-gray-800 hover:text-white"
                    )
                  ]}
                >
                  <%= vinyl_icon_sm() %>
                  <div class="flex-1 min-w-0">
                    <p class="font-medium truncate">{crate.name}</p>
                    <p class="text-gray-600 truncate">{length(crate.playlist_data || [])} tracks</p>
                  </div>
                </button>
              </li>
            </ul>
          </div>
        </aside>

        <!-- Center panel: track list -->
        <div class="flex-1 flex flex-col overflow-hidden">
          <!-- Stem config bar -->
          <div :if={@active_crate} class="flex items-center gap-3 px-4 py-2.5 bg-gray-900/50 border-b border-gray-800 shrink-0">
            <span class="text-xs text-gray-500">Stems:</span>
            <%= for stem <- ["vocals", "drums", "bass", "other"] do %>
              <button
                phx-click="toggle_stem"
                phx-value-stem={stem}
                class={[
                  "px-2.5 py-1 rounded text-xs font-medium transition-colors",
                  if(stem in (@active_crate.stem_config["enabled_stems"] || []),
                    do: "bg-purple-600 text-white",
                    else: "bg-gray-800 text-gray-500 hover:bg-gray-700"
                  )
                ]}
              >
                {stem}
              </button>
            <% end %>
            <span class="ml-2 text-xs text-gray-600">
              Playing: {Enum.join(@active_crate.stem_config["enabled_stems"] || [], " + ")}
            </span>
          </div>

          <!-- Track list -->
          <div class="flex-1 overflow-y-auto" id="crate-track-list">
            <!-- No active crate -->
            <div :if={is_nil(@active_crate)} class="flex flex-col items-center justify-center h-full text-center px-8">
              <%= vinyl_icon_lg() %>
              <p class="mt-4 text-gray-500 text-sm">Select a crate to view tracks</p>
            </div>

            <!-- Skeleton loading -->
            <div :if={@active_crate && @playlist_loading} class="divide-y divide-gray-800">
              <%= for _i <- 1..6 do %>
                <div class="flex items-center gap-3 px-4 py-3 animate-pulse">
                  <div class="w-10 h-10 rounded bg-gray-800 shrink-0"></div>
                  <div class="flex-1 space-y-2">
                    <div class="h-3 bg-gray-800 rounded w-2/3"></div>
                    <div class="h-2.5 bg-gray-800 rounded w-1/3"></div>
                  </div>
                  <div class="h-2.5 bg-gray-800 rounded w-10"></div>
                </div>
              <% end %>
            </div>

            <!-- Track rows -->
            <div :if={@active_crate && not @playlist_loading} class="divide-y divide-gray-800/50">
              <div :if={@active_crate.playlist_data == []} class="flex flex-col items-center justify-center py-16 text-center px-8">
                <p class="text-gray-500 text-sm">No tracks in this playlist</p>
              </div>

              <%= for {track, idx} <- Enum.with_index(@active_crate.playlist_data || []) do %>
                <div
                  class={[
                    "flex items-center gap-3 px-4 py-2.5 cursor-pointer hover:bg-gray-800/40 transition-colors group",
                    if(@inspector_track && @inspector_track["spotify_id"] == track["spotify_id"],
                      do: "bg-purple-900/20",
                      else: ""
                    )
                  ]}
                  phx-click="open_inspector"
                  phx-value-index={idx}
                >
                  <!-- Artwork -->
                  <div class="w-10 h-10 rounded bg-gray-800 shrink-0 overflow-hidden">
                    <%= if track["artwork_url"] do %>
                      <img src={track["artwork_url"]} alt={track["title"]} class="w-full h-full object-cover" />
                    <% else %>
                      <div class="w-full h-full flex items-center justify-center text-gray-600">
                        <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                          <path d="M12 2a10 10 0 100 20A10 10 0 0012 2zm0 3a7 7 0 110 14A7 7 0 0112 5zm0 2a5 5 0 100 10A5 5 0 0012 7zm0 2a3 3 0 110 6A3 3 0 0112 9z"/>
                        </svg>
                      </div>
                    <% end %>
                  </div>

                  <!-- Track info -->
                  <div class="flex-1 min-w-0">
                    <p class="text-sm text-gray-200 truncate">{track["title"]}</p>
                    <p class="text-xs text-gray-500 truncate">{track["artist"]}</p>
                  </div>

                  <!-- Override badge + duration -->
                  <div class="flex items-center gap-2 shrink-0">
                    <span :if={has_override?(@active_crate, track["spotify_id"])} class="px-1.5 py-0.5 rounded text-xs bg-amber-500/20 text-amber-400 font-medium">
                      override
                    </span>
                    <!-- Analysis badge -->
                    <span :if={load_analysis(track["spotify_id"])} class="w-1.5 h-1.5 rounded-full bg-green-500 shrink-0" title="Analysis available"></span>
                    <span class="text-xs text-gray-600 tabular-nums">{format_duration(track["duration_ms"])}</span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Right panel: inspector (slide in/out) -->
        <div
          class={[
            "absolute top-0 right-0 h-full w-80 bg-gray-900 border-l border-gray-800 flex flex-col z-30 transition-transform duration-300 ease-in-out",
            "md:w-96",
            if(@inspector_open, do: "translate-x-0", else: "translate-x-full")
          ]}
          id="crate-inspector"
        >
          <%= if @inspector_track do %>
            <!-- Inspector header -->
            <div class="flex items-start gap-3 px-4 py-4 border-b border-gray-800 shrink-0">
              <div class="w-12 h-12 rounded bg-gray-800 shrink-0 overflow-hidden">
                <%= if @inspector_track["artwork_url"] do %>
                  <img src={@inspector_track["artwork_url"]} alt={@inspector_track["title"]} class="w-full h-full object-cover" />
                <% else %>
                  <div class="w-full h-full flex items-center justify-center text-gray-600">
                    <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 24 24"><path d="M12 2a10 10 0 100 20A10 10 0 0012 2zm0 3a7 7 0 110 14A7 7 0 0112 5zm0 2a5 5 0 100 10A5 5 0 0012 7zm0 2a3 3 0 110 6A3 3 0 0112 9z"/></svg>
                  </div>
                <% end %>
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-white truncate">{@inspector_track["title"]}</p>
                <p class="text-xs text-gray-400 truncate">{@inspector_track["artist"]}</p>
              </div>
              <button phx-click="close_inspector" class="text-gray-500 hover:text-white transition-colors mt-0.5">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <!-- Accordion sections -->
            <div class="flex-1 overflow-y-auto divide-y divide-gray-800">

              <!-- WhoSampled -->
              <div>
                <button phx-click="toggle_section" phx-value-section="whosampled" class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-gray-300 hover:text-white hover:bg-gray-800/30 transition-colors">
                  WhoSampled
                  <svg class={["w-4 h-4 text-gray-500 transition-transform", if(@section_open.whosampled, do: "rotate-180", else: "")]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
                </button>
                <div :if={@section_open.whosampled} class="px-4 pb-3">
                  <div :if={@whosampled_loading} class="flex items-center gap-2 py-4 text-gray-500 text-sm">
                    <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"/></svg>
                    Fetching samples...
                  </div>
                  <div :if={not @whosampled_loading and @whosampled_error == :rate_limited} class="py-4">
                    <p class="text-xs text-amber-400">WhoSampled is rate-limiting requests.</p>
                    <button phx-click="toggle_section" phx-value-section="whosampled" class="mt-2 text-xs text-purple-400 hover:text-purple-300">Retry</button>
                  </div>
                  <div :if={not @whosampled_loading and @whosampled_error not in [nil, :rate_limited]} class="py-4">
                    <p class="text-xs text-red-400">Failed to load sample data.</p>
                    <button phx-click="toggle_section" phx-value-section="whosampled" class="mt-2 text-xs text-purple-400 hover:text-purple-300">Retry</button>
                  </div>
                  <p :if={not @whosampled_loading and is_nil(@whosampled_error) and @whosampled_samples == []} class="py-4 text-xs text-gray-500">No sample data found on WhoSampled.</p>
                  <p :if={not @whosampled_loading and is_nil(@whosampled_samples) and is_nil(@whosampled_error)} class="py-4 text-xs text-gray-500">Expand to load sample data.</p>
                  <div :if={not @whosampled_loading and is_list(@whosampled_samples) and @whosampled_samples != []} class="space-y-3 py-2">
                    <div :for={sample <- @whosampled_samples} class="rounded-md bg-gray-800/50 p-3 space-y-1.5">
                      <div class="flex items-start justify-between gap-2">
                        <div class="min-w-0">
                          <p class="text-sm font-medium text-gray-200 truncate">{sample["title"]}</p>
                          <p class="text-xs text-gray-400">{sample["artist"]}{if sample["year"], do: " · #{sample["year"]}", else: ""}</p>
                        </div>
                        <span class={["px-1.5 py-0.5 rounded text-xs font-medium shrink-0", sample_type_class(sample["sample_type"])]}>{sample["sample_type"]}</span>
                      </div>
                      <div class="flex items-center gap-2">
                        <a :if={sample["spotify_url"]} href={sample["spotify_url"]} target="_blank" rel="noopener" class="text-xs text-green-400 hover:text-green-300">Spotify</a>
                        <a :if={sample["youtube_url"]} href={sample["youtube_url"]} target="_blank" rel="noopener" class="text-xs text-red-400 hover:text-red-300">YouTube</a>
                        <button :if={sample["spotify_url"]} phx-click="load_into_sfa" phx-value-spotify_url={sample["spotify_url"]} class="ml-auto text-xs text-purple-400 hover:text-purple-300">Load into SFA</button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Track Details -->
              <div>
                <button phx-click="toggle_section" phx-value-section="details" class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-gray-300 hover:text-white hover:bg-gray-800/30 transition-colors">
                  Track Details
                  <svg class={["w-4 h-4 text-gray-500 transition-transform", if(@section_open.details, do: "rotate-180", else: "")]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
                </button>
                <div :if={@section_open.details} class="px-4 pb-3">
                  <dl class="space-y-2 py-2 text-xs">
                    <div :if={@inspector_track["album"]} class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Album</dt>
                      <dd class="text-gray-300 text-right">{@inspector_track["album"]}</dd>
                    </div>
                    <div :if={format_artists(@inspector_track["artists"])} class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Artists</dt>
                      <dd class="text-gray-300 text-right">{format_artists(@inspector_track["artists"])}</dd>
                    </div>
                    <div :if={format_release_date(@inspector_track["release_date"])} class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Released</dt>
                      <dd class="text-gray-300 text-right">{format_release_date(@inspector_track["release_date"])}</dd>
                    </div>
                    <div class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Duration</dt>
                      <dd class="text-gray-300 text-right">{format_duration(@inspector_track["duration_ms"])}</dd>
                    </div>
                    <div class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Explicit</dt>
                      <dd class="text-gray-300 text-right">{if @inspector_track["explicit"], do: "Yes", else: "No"}</dd>
                    </div>
                    <div :if={@inspector_track["popularity"]} class="flex justify-between gap-2">
                      <dt class="text-gray-500 shrink-0">Popularity</dt>
                      <dd class="text-gray-300 text-right">{@inspector_track["popularity"]}/100</dd>
                    </div>
                  </dl>
                </div>
              </div>

              <!-- Lyrics -->
              <div>
                <button phx-click="toggle_section" phx-value-section="lyrics" class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-gray-300 hover:text-white hover:bg-gray-800/30 transition-colors">
                  Lyrics
                  <svg class={["w-4 h-4 text-gray-500 transition-transform", if(@section_open.lyrics, do: "rotate-180", else: "")]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
                </button>
                <div :if={@section_open.lyrics} class="px-4 pb-3 py-2">
                  <a
                    href={"https://genius.com/search?q=#{URI.encode("#{@inspector_track["artist"]} #{@inspector_track["title"]}")}"}
                    target="_blank"
                    rel="noopener"
                    class="flex items-center gap-2 text-sm text-yellow-400 hover:text-yellow-300 transition-colors"
                  >
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z"/></svg>
                    View on Genius
                    <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/></svg>
                  </a>
                </div>
              </div>

              <!-- Analysis -->
              <div>
                <button phx-click="toggle_section" phx-value-section="analysis" class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-gray-300 hover:text-white hover:bg-gray-800/30 transition-colors">
                  Analysis
                  <svg class={["w-4 h-4 text-gray-500 transition-transform", if(@section_open.analysis, do: "rotate-180", else: "")]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
                </button>
                <div :if={@section_open.analysis} class="px-4 pb-3">
                  <%= if @inspector_analysis do %>
                    <dl class="space-y-3 py-2 text-xs">
                      <div :if={format_bpm(@inspector_analysis)} class="flex justify-between gap-2">
                        <dt class="text-gray-500">BPM</dt><dd class="text-gray-300">{format_bpm(@inspector_analysis)}</dd>
                      </div>
                      <div :if={format_key(@inspector_analysis)} class="flex justify-between gap-2">
                        <dt class="text-gray-500">Key</dt><dd class="text-gray-300">{format_key(@inspector_analysis)}</dd>
                      </div>
                      <div>
                        <dt class="text-gray-500 mb-1">Energy</dt>
                        <dd>
                          <div class="w-full bg-gray-800 rounded-full h-1.5">
                            <div class="bg-purple-500 h-1.5 rounded-full" style={"width: #{format_energy_pct(@inspector_analysis)}%"}></div>
                          </div>
                        </dd>
                      </div>
                      <div>
                        <dt class="text-gray-500 mb-1.5">Stems</dt>
                        <dd>
                          <div class="grid grid-cols-4 gap-1.5 text-center text-xs">
                            <div :for={stem <- ["vocals", "drums", "bass", "other"]} class={["rounded px-1 py-1.5", if(stem_available?(@inspector_analysis, stem), do: "bg-green-900/40 text-green-400", else: "bg-gray-800 text-gray-600")]}>
                              {stem}
                            </div>
                          </div>
                        </dd>
                      </div>
                    </dl>
                  <% else %>
                    <div class="py-3">
                      <p class="text-xs text-gray-500 mb-3">No analysis data available.</p>
                      <%= if find_sfa_track(@inspector_track["spotify_id"]) do %>
                        <% sfa_track = find_sfa_track(@inspector_track["spotify_id"]) %>
                        <button phx-click="trigger_analysis" phx-value-track_id={sfa_track.id} class="px-3 py-1.5 text-xs bg-purple-600 hover:bg-purple-500 rounded text-white transition-colors">
                          Trigger Analysis
                        </button>
                      <% else %>
                        <p class="text-xs text-gray-600">Track not in SFA library yet. Download it first.</p>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Per-track stem override -->
              <div>
                <button phx-click="toggle_section" phx-value-section="stems" class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-gray-300 hover:text-white hover:bg-gray-800/30 transition-colors">
                  Stem Override
                  <svg class={["w-4 h-4 text-gray-500 transition-transform", if(@section_open.stems, do: "rotate-180", else: "")]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
                </button>
                <div :if={@section_open.stems and @active_crate} class="px-4 pb-3 py-2 space-y-3">
                  <% override = get_track_override(@active_crate, @inspector_track["spotify_id"]) %>
                  <% effective = override || @active_crate.stem_config["enabled_stems"] || ["vocals", "drums", "bass", "other"] %>
                  <% is_overridden = not is_nil(override) %>
                  <p class="text-xs text-gray-500">
                    <span :if={is_overridden} class="text-amber-400 font-medium">Per-track override active.</span>
                    <span :if={not is_overridden}>Using playlist default. Toggle stems to override.</span>
                  </p>
                  <div class="flex flex-wrap gap-1.5">
                    <button :for={stem <- ["vocals", "drums", "bass", "other"]}
                      phx-click="toggle_track_stem"
                      phx-value-stem={stem}
                      class={["px-2.5 py-1 rounded text-xs font-medium transition-colors",
                        if(stem in effective,
                          do: if(is_overridden, do: "bg-amber-600 text-white", else: "bg-purple-600 text-white"),
                          else: "bg-gray-800 text-gray-500 hover:bg-gray-700"
                        )
                      ]}
                    >{stem}</button>
                  </div>
                  <button :if={is_overridden} phx-click="clear_track_override" class="text-xs text-gray-400 hover:text-white transition-colors">
                    Reset to playlist default
                  </button>
                </div>
              </div>

            </div>
          <% end %>
        </div>

        <!-- Backdrop for mobile -->
        <div
          :if={@inspector_open}
          class="absolute inset-0 bg-black/50 z-20 md:hidden"
          phx-click="close_inspector"
        ></div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp active_tracks(socket) do
    case socket.assigns.active_crate do
      nil -> []
      crate -> crate.playlist_data || []
    end
  end

  defp reload_crates(socket) do
    case socket.assigns.current_user do
      nil -> []
      user -> CrateDigger.list_crates(user.id)
    end
  end

  defp load_analysis(nil), do: nil

  defp load_analysis(spotify_id) do
    # Find by spotify_id on Track, then look up analysis
    import Ecto.Query

    track =
      Repo.one(
        from t in SoundForge.Music.Track,
          where: t.spotify_id == ^spotify_id,
          limit: 1
      )

    if track do
      Music.get_analysis_result_for_track(track.id)
    else
      nil
    end
  end

  defp find_sfa_track(nil), do: nil

  defp find_sfa_track(spotify_id) do
    import Ecto.Query

    Repo.one(
      from t in SoundForge.Music.Track,
        where: t.spotify_id == ^spotify_id,
        limit: 1
    )
  end

  defp has_override?(nil, _), do: false

  defp has_override?(crate, spotify_track_id) do
    Enum.any?(crate.track_configs || [], fn tc ->
      tc.spotify_track_id == spotify_track_id && not is_nil(tc.stem_override)
    end)
  end

  defp get_track_override(nil, _), do: nil

  defp get_track_override(crate, spotify_track_id) do
    case Enum.find(crate.track_configs || [], &(&1.spotify_track_id == spotify_track_id)) do
      %{stem_override: %{"enabled_stems" => stems}} when is_list(stems) -> stems
      _ -> nil
    end
  end

  defp resolve_user(%{id: _} = user, _session), do: user

  defp resolve_user(_, session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _} <- Accounts.get_user_by_session_token(token) do
      user
    else
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Formatting helpers
  # ---------------------------------------------------------------------------

  defp format_duration(nil), do: "--:--"

  defp format_duration(ms) when is_integer(ms) do
    seconds = div(ms, 1000)
    m = div(seconds, 60)
    s = rem(seconds, 60)
    :io_lib.format("~B:~2..0B", [m, s]) |> to_string()
  end

  defp format_duration(_), do: "--:--"

  defp format_artists(nil), do: nil
  defp format_artists([]), do: nil
  defp format_artists(artists) when is_list(artists), do: Enum.join(artists, ", ")
  defp format_artists(artist) when is_binary(artist), do: artist

  defp format_release_date(nil), do: nil

  defp format_release_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        Calendar.strftime(date, "%B %d %Y")

      _ ->
        # year-only fallback
        case Regex.run(~r/^\d{4}/, date_str) do
          [year] -> year
          _ -> date_str
        end
    end
  end

  defp format_release_date(_), do: nil

  defp format_popularity(nil), do: nil
  defp format_popularity(n) when is_integer(n), do: "#{n}/100"
  defp format_popularity(_), do: nil

  defp format_bpm(%{features: %{"tempo" => bpm}}) when is_number(bpm), do: "#{round(bpm)} BPM"
  defp format_bpm(_), do: nil

  defp format_key(%{features: %{"key" => key, "mode" => mode}}) do
    keys = ~w(C C# D D# E F F# G G# A A# B)
    key_name = Enum.at(keys, key || 0, "?")
    mode_name = if mode == 1, do: "Major", else: "Minor"
    "#{key_name} #{mode_name}"
  end

  defp format_key(_), do: nil

  defp format_energy_pct(%{features: %{"energy" => e}}) when is_number(e), do: round(e * 100)
  defp format_energy_pct(_), do: 0

  defp stem_available?(%{features: features}, stem) when is_map(features) do
    Map.get(features, "stems_#{stem}") == true or Map.get(features, stem) == true
  end

  defp stem_available?(_, _), do: false

  defp sample_type_class("direct"), do: "bg-purple-500/20 text-purple-300"
  defp sample_type_class("interpolation"), do: "bg-blue-500/20 text-blue-300"
  defp sample_type_class("replayed"), do: "bg-green-500/20 text-green-300"
  defp sample_type_class(_), do: "bg-gray-700 text-gray-400"

  # ---------------------------------------------------------------------------
  # SVG icons
  # ---------------------------------------------------------------------------

  defp vinyl_icon do
    Phoenix.HTML.raw("""
    <svg class="w-5 h-5 text-purple-400 shrink-0" fill="currentColor" viewBox="0 0 24 24">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 14c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm0-6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/>
    </svg>
    """)
  end

  defp vinyl_icon_sm do
    Phoenix.HTML.raw("""
    <svg class="w-3.5 h-3.5 shrink-0 text-gray-500" fill="currentColor" viewBox="0 0 24 24">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 14c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm0-6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/>
    </svg>
    """)
  end

  defp vinyl_icon_lg do
    Phoenix.HTML.raw("""
    <svg class="w-12 h-12 text-gray-700 mx-auto" fill="currentColor" viewBox="0 0 24 24">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 14c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm0-6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/>
    </svg>
    """)
  end
end
