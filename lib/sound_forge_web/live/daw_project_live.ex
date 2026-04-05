defmodule SoundForgeWeb.Live.DawProjectLive do
  use SoundForgeWeb, :live_view

  alias SoundForge.DAW
  alias SoundForge.Music
  alias SoundForge.CrateDigger
  alias SoundForge.Accounts

  @impl true
  def mount(_params, session, socket) do
    user_id = resolve_user_id(socket.assigns[:current_user], session)

    if connected?(socket) do
      SoundForge.MIDI.GlobalBroadcaster.subscribe()
    end

    projects = if user_id, do: DAW.list_projects(user_id), else: []
    active_project = List.first(projects)

    # Load full project with preloaded tracks
    active_project =
      if active_project, do: DAW.get_project!(active_project.id), else: nil

    {:ok,
     assign(socket,
       current_user_id: user_id,
       projects: projects,
       active_project: active_project,
       add_track_open: false,
       import_source: :library,
       library_tracks: [],
       library_search: "",
       selected_track_ids: MapSet.new(),
       last_selected_index: nil,
       user_crates: [],
       selected_crate_id: nil,
       crate_matched_tracks: [],
       track_override_id: nil,
       page_title: "DAW",
       midi_bar_position: "bottom",
       midi_learn_active: false,
       midi_monitor_open: false
     )}
  end

  @impl true
  def handle_params(%{"track_id" => track_id}, _uri, socket) do
    user_id = socket.assigns.current_user_id

    uuid_format = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

    with true <- user_id != nil,
         true <- String.match?(track_id, uuid_format),
         {:ok, kind, project} <- DAW.get_or_create_project_with_track(user_id, track_id) do
      projects = DAW.list_projects(user_id)
      msg = if kind == :added, do: "Track added to \"#{project.title}\"", else: "Track already in project"
      {:noreply, socket |> assign(active_project: project, projects: projects) |> put_flash(:info, msg)}
    else
      false -> {:noreply, put_flash(socket, :error, "Invalid track ID")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not load track in DAW")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp reload_project(socket, project_id) do
    project = DAW.get_project!(project_id)
    user_id = socket.assigns.current_user_id
    projects = if user_id, do: DAW.list_projects(user_id), else: []
    assign(socket, active_project: project, projects: projects)
  end

  defp badge_class("full_track"), do: "badge badge-sm bg-blue-600 text-white border-0"
  defp badge_class("loop"), do: "badge badge-sm bg-green-600 text-white border-0"
  defp badge_class("drum_loop"), do: "badge badge-sm bg-orange-600 text-white border-0"
  defp badge_class("sample_loop"), do: "badge badge-sm bg-yellow-600 text-gray-900 border-0"
  defp badge_class(_), do: "badge badge-sm bg-gray-600 text-white border-0"

  defp badge_label("full_track"), do: "Full Track"
  defp badge_label("loop"), do: "Loop"
  defp badge_label("drum_loop"), do: "Drum Loop"
  defp badge_label("sample_loop"), do: "Sample Loop"
  defp badge_label(_), do: "Unknown"

  defp format_duration(nil), do: "—"

  defp format_duration(seconds) when is_integer(seconds) do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    :io_lib.format("~B:~2..0B", [m, s]) |> IO.iodata_to_binary()
  end

  defp format_duration(ms) when is_float(ms), do: format_duration(round(ms / 1000))

  defp scope(socket), do: %{user: %{id: socket.assigns.current_user_id}}

  defp project_tracks_json(nil), do: []

  defp project_tracks_json(project) do
    Enum.map(project.project_tracks || [], fn track ->
      %{
        id: track.id,
        title: track.title || (track.audio_file && track.audio_file.title) || "Track",
        position: track.position,
        track_type: track.track_type,
        duration_ms: track.audio_file && track.audio_file.duration_ms,
        bpm: track.audio_file && track.audio_file.bpm
      }
    end)
  end

  defp project_track_types(nil), do: %{}

  defp project_track_types(project) do
    (project.project_tracks || [])
    |> Enum.reduce(%{}, fn track, acc ->
      Map.put(acc, track.id, track.track_type)
    end)
  end

  # ---------------------------------------------------------------------------
  # Event handlers — project management
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("new_project", _params, socket) do
    user_id = socket.assigns.current_user_id

    case DAW.create_project(user_id, %{title: "Untitled Project"}) do
      {:ok, project} ->
        full_project = DAW.get_project!(project.id)
        projects = DAW.list_projects(user_id)
        {:noreply, assign(socket, projects: projects, active_project: full_project)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create project")}
    end
  end

  def handle_event("select_project", %{"id" => id}, socket) do
    project = DAW.get_project!(id)
    {:noreply, assign(socket, active_project: project)}
  end

  def handle_event("save_project_title", %{"value" => title}, socket) do
    project = socket.assigns.active_project

    case DAW.update_project(project, %{title: title}) do
      {:ok, updated} ->
        projects = DAW.list_projects(socket.assigns.current_user_id)
        {:noreply, assign(socket, active_project: updated, projects: projects)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save project title")}
    end
  end

  def handle_event("update_project_bpm", %{"bpm" => bpm_str}, socket) do
    project = socket.assigns.active_project

    case Integer.parse(bpm_str) do
      {bpm, _} ->
        case DAW.update_project(project, %{bpm: bpm}) do
          {:ok, updated} -> {:noreply, assign(socket, active_project: updated)}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update BPM")}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("update_project_key", %{"key" => key}, socket) do
    project = socket.assigns.active_project

    case DAW.update_project(project, %{key: key}) do
      {:ok, updated} -> {:noreply, assign(socket, active_project: updated)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update key")}
    end
  end

  def handle_event("update_project_time_sig", %{"time_sig" => time_sig}, socket) do
    project = socket.assigns.active_project

    case DAW.update_project(project, %{time_sig: time_sig}) do
      {:ok, updated} -> {:noreply, assign(socket, active_project: updated)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update time signature")}
    end
  end

  # ---------------------------------------------------------------------------
  # Event handlers — track management
  # ---------------------------------------------------------------------------

  def handle_event("open_add_track", _params, socket) do
    scope = scope(socket)
    library_tracks = Music.list_tracks(scope)

    {:noreply,
     assign(socket,
       add_track_open: true,
       import_source: :library,
       library_tracks: library_tracks,
       library_search: "",
       selected_track_ids: MapSet.new(),
       last_selected_index: nil
     )}
  end

  def handle_event("close_add_track", _params, socket) do
    {:noreply,
     assign(socket,
       add_track_open: false,
       selected_track_ids: MapSet.new(),
       selected_crate_id: nil,
       crate_matched_tracks: []
     )}
  end

  def handle_event("set_import_source", %{"source" => source}, socket) do
    source_atom = if source == "crate", do: :crate, else: :library

    socket =
      if source_atom == :library do
        scope = scope(socket)
        library_tracks = Music.list_tracks(scope)
        assign(socket, library_tracks: library_tracks, library_search: "")
      else
        user_id = socket.assigns.current_user_id
        crates = CrateDigger.list_crates(user_id)
        assign(socket, user_crates: crates, selected_crate_id: nil, crate_matched_tracks: [])
      end

    {:noreply,
     assign(socket,
       import_source: source_atom,
       selected_track_ids: MapSet.new(),
       last_selected_index: nil
     )}
  end

  def handle_event("toggle_track_selection", %{"track-id" => track_id} = params, socket) do
    index = params["index"] && String.to_integer(params["index"])
    selected = socket.assigns.selected_track_ids

    new_selected =
      if MapSet.member?(selected, track_id) do
        MapSet.delete(selected, track_id)
      else
        MapSet.put(selected, track_id)
      end

    {:noreply, assign(socket, selected_track_ids: new_selected, last_selected_index: index)}
  end

  def handle_event("select_all_tracks", _params, socket) do
    tracks =
      case socket.assigns.import_source do
        :library -> socket.assigns.library_tracks
        :crate -> socket.assigns.crate_matched_tracks
      end

    all_ids = MapSet.new(tracks, & &1.id)
    {:noreply, assign(socket, selected_track_ids: all_ids)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_track_ids: MapSet.new(), last_selected_index: nil)}
  end

  def handle_event("select_crate_to_browse", %{"crate-id" => crate_id}, socket) do
    scope = scope(socket)
    crate = CrateDigger.get_crate(crate_id)

    crate_matched_tracks =
      if crate do
        spotify_ids =
          (crate.track_configs || [])
          |> Enum.map(& &1.spotify_track_id)
          |> Enum.reject(&is_nil/1)

        Music.list_tracks(scope)
        |> Enum.filter(fn t -> t.spotify_id in spotify_ids end)
      else
        []
      end

    {:noreply,
     assign(socket,
       selected_crate_id: crate_id,
       crate_matched_tracks: crate_matched_tracks,
       selected_track_ids: MapSet.new()
     )}
  end

  def handle_event("back_to_crate_list", _params, socket) do
    {:noreply,
     assign(socket,
       selected_crate_id: nil,
       crate_matched_tracks: [],
       selected_track_ids: MapSet.new()
     )}
  end

  def handle_event("add_selected_tracks", _params, socket) do
    project = socket.assigns.active_project
    track_ids = MapSet.to_list(socket.assigns.selected_track_ids)
    base_position = length(project.project_tracks)

    {imported, errors} =
      track_ids
      |> Enum.with_index()
      |> Enum.reduce({0, 0}, fn {track_id, i}, {ok, err} ->
        track = Music.get_track!(track_id)

        attrs = %{
          audio_file_id: track.id,
          title: track.title,
          position: base_position + i,
          track_type: "unknown"
        }

        case DAW.add_track(project.id, attrs) do
          {:ok, _} -> {ok + 1, err}
          {:error, _} -> {ok, err + 1}
        end
      end)

    socket =
      socket
      |> reload_project(project.id)
      |> assign(add_track_open: false, selected_track_ids: MapSet.new())

    socket =
      if errors > 0 do
        put_flash(socket, :error, "Added #{imported} track(s), #{errors} failed")
      else
        put_flash(socket, :info, "Added #{imported} track(s)")
      end

    {:noreply, socket}
  end

  def handle_event("search_library", %{"query" => query}, socket) do
    scope = scope(socket)

    tracks =
      if query == "" do
        Music.list_tracks(scope)
      else
        Music.search_tracks(query, scope)
      end

    {:noreply, assign(socket, library_tracks: tracks, library_search: query)}
  end

  def handle_event("remove_track", %{"id" => id}, socket) do
    project = socket.assigns.active_project

    case DAW.remove_track(id) do
      {:ok, _} -> {:noreply, reload_project(socket, project.id)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not remove track")}
    end
  end

  def handle_event("set_track_override", %{"id" => id}, socket) do
    {:noreply, assign(socket, track_override_id: id)}
  end

  def handle_event("cancel_track_override", _params, socket) do
    {:noreply, assign(socket, track_override_id: nil)}
  end

  def handle_event("override_track_type", %{"track-id" => track_id, "type" => type}, socket) do
    project = socket.assigns.active_project

    track = Enum.find(project.project_tracks, fn t -> t.id == track_id end)

    if track do
      case DAW.update_track_type(track, %{type: type, manual: true}) do
        {:ok, _} ->
          {:noreply,
           socket
           |> reload_project(project.id)
           |> assign(track_override_id: nil)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not update track type")}
      end
    else
      {:noreply, assign(socket, track_override_id: nil)}
    end
  end

  def handle_event("auto_classify_all", _params, socket) do
    project = socket.assigns.active_project

    %{"project_id" => project.id}
    |> SoundForge.Jobs.DawClassifyWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Classification queued for all tracks")}
  end

  # ---------------------------------------------------------------------------
  # Event handlers — crate import (shortcut: opens unified panel on Crate tab)
  # ---------------------------------------------------------------------------

  def handle_event("open_import_crate", _params, socket) do
    user_id = socket.assigns.current_user_id
    crates = CrateDigger.list_crates(user_id)

    {:noreply,
     assign(socket,
       add_track_open: true,
       import_source: :crate,
       user_crates: crates,
       selected_track_ids: MapSet.new(),
       selected_crate_id: nil,
       crate_matched_tracks: []
     )}
  end

  # ---------------------------------------------------------------------------
  # MIDI bar
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:midi_global_event, port_id, msg}, socket) do
    send_update(SoundForgeWeb.Live.Components.GlobalMidiBarComponent,
      id: "global-midi-bar",
      midi_event: {port_id, msg}
    )
    {:noreply, socket}
  end

  def handle_info({:global_midi_bar, :toggle_monitor, open}, socket) do
    {:noreply, assign(socket, :midi_monitor_open, open)}
  end

  def handle_info({:global_midi_bar, :toggle_learn, active}, socket) do
    {:noreply, assign(socket, :midi_learn_active, active)}
  end

  def handle_info({:global_midi_bar, :set_position, pos}, socket) do
    {:noreply, assign(socket, :midi_bar_position, pos)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full min-h-screen bg-gray-950 text-gray-100 relative overflow-hidden">
      <.live_component
        module={SoundForgeWeb.Live.Components.GlobalMidiBarComponent}
        id="global-midi-bar"
        position={@midi_bar_position}
        visible={true}
        midi_monitor_open={@midi_monitor_open}
        midi_learn_active={@midi_learn_active}
      />

      <!-- Project sidebar (left, w-64) -->
      <aside class="w-64 flex-shrink-0 bg-gray-900 border-r border-gray-800 flex flex-col">
        <div class="p-4 border-b border-gray-800">
          <h2 class="text-sm font-semibold text-gray-400 uppercase tracking-wider mb-3">Projects</h2>
          <button
            phx-click="new_project"
            class="btn btn-sm btn-primary w-full"
          >
            + New Project
          </button>
        </div>

        <nav class="flex-1 overflow-y-auto py-2">
          <%= for project <- @projects do %>
            <button
              phx-click="select_project"
              phx-value-id={project.id}
              class={[
                "w-full text-left px-4 py-3 flex items-center justify-between hover:bg-gray-800 transition-colors",
                @active_project && @active_project.id == project.id &&
                  "bg-gray-800 border-l-2 border-primary"
              ]}
            >
              <span class="text-sm text-gray-200 truncate flex-1 mr-2"><%= project.title %></span>
              <span class="badge badge-sm badge-ghost text-gray-500">
                <%= length(project.project_tracks) %>
              </span>
            </button>
          <% end %>
        </nav>

        <!-- Active project metadata controls -->
        <%= if @active_project do %>
          <div class="p-4 border-t border-gray-800 space-y-3">
            <div>
              <label class="text-xs text-gray-500 mb-1 block">Title</label>
              <input
                type="text"
                value={@active_project.title}
                phx-blur="save_project_title"
                class="input input-xs input-bordered bg-gray-800 border-gray-700 text-gray-100 w-full"
              />
            </div>
            <div class="flex gap-2">
              <div class="flex-1">
                <label class="text-xs text-gray-500 mb-1 block">BPM</label>
                <form phx-change="update_project_bpm">
                  <input
                    type="number"
                    name="bpm"
                    value={@active_project.bpm}
                    min="40"
                    max="300"
                    class="input input-xs input-bordered bg-gray-800 border-gray-700 text-gray-100 w-full"
                  />
                </form>
              </div>
              <div class="flex-1">
                <label class="text-xs text-gray-500 mb-1 block">Sig</label>
                <form phx-change="update_project_time_sig">
                  <select
                    name="time_sig"
                    class="select select-xs select-bordered bg-gray-800 border-gray-700 text-gray-100 w-full"
                  >
                    <%= for sig <- ["4/4", "3/4", "6/8", "5/4"] do %>
                      <option value={sig} selected={@active_project.time_sig == sig}><%= sig %></option>
                    <% end %>
                  </select>
                </form>
              </div>
            </div>
            <div>
              <label class="text-xs text-gray-500 mb-1 block">Key</label>
              <form phx-change="update_project_key">
                <select
                  name="key"
                  class="select select-xs select-bordered bg-gray-800 border-gray-700 text-gray-100 w-full"
                >
                  <option value="" selected={is_nil(@active_project.key) || @active_project.key == ""}>
                    — None —
                  </option>
                  <%= for key <- ~w[C C# Db D D# Eb E F F# Gb G G# Ab A A# Bb B] do %>
                    <option value={key} selected={@active_project.key == key}><%= key %></option>
                  <% end %>
                </select>
              </form>
            </div>
          </div>
        <% end %>
      </aside>

      <!-- Main content area -->
      <main class="flex-1 flex flex-col overflow-hidden">
        <%= if @active_project do %>
          <!-- Track panel header -->
          <header class="flex items-center justify-between px-6 py-4 border-b border-gray-800 bg-gray-900">
            <h1 class="text-lg font-semibold text-gray-100">
              Tracks
              <span class="text-sm font-normal text-gray-500 ml-2">
                <%= length(@active_project.project_tracks) %> track(s)
              </span>
            </h1>
            <div class="flex items-center gap-2">
              <button
                phx-click="auto_classify_all"
                class="btn btn-sm btn-ghost text-gray-400 hover:text-gray-200"
              >
                Auto-classify all
              </button>
              <button
                phx-click="open_import_crate"
                class="btn btn-sm btn-ghost text-gray-400 hover:text-gray-200"
              >
                Import from Crate
              </button>
              <button
                phx-click="open_add_track"
                class="btn btn-sm btn-primary"
              >
                + Add Track
              </button>
            </div>
          </header>

          <!-- Multi-track timeline editor -->
          <div
            id="daw-project-editor"
            phx-hook="DawProjectEditor"
            data-project-id={@active_project && @active_project.id}
            data-tracks={Jason.encode!(project_tracks_json(@active_project))}
            data-track-types={Jason.encode!(project_track_types(@active_project))}
            class="flex-none min-h-24 bg-gray-900 border-b border-gray-800"
          >
            <p class="text-gray-500 p-4 text-sm">Timeline editor</p>
          </div>

          <!-- Track list -->
          <div class="flex-1 overflow-y-auto">
            <%= if Enum.empty?(@active_project.project_tracks) do %>
              <div class="flex flex-col items-center justify-center h-full text-center py-24">
                <div class="text-4xl mb-4">🎵</div>
                <h3 class="text-lg font-medium text-gray-300 mb-2">No tracks yet</h3>
                <p class="text-gray-500 text-sm mb-6">
                  Add tracks from your library to start arranging.
                </p>
                <button phx-click="open_add_track" class="btn btn-primary btn-sm">
                  + Add Track
                </button>
              </div>
            <% else %>
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-gray-800 text-gray-500 text-xs uppercase tracking-wider">
                    <th class="px-4 py-3 text-left w-10">#</th>
                    <th class="px-4 py-3 text-left">Title</th>
                    <th class="px-4 py-3 text-left">Type</th>
                    <th class="px-4 py-3 text-left">Duration</th>
                    <th class="px-4 py-3 text-left">BPM</th>
                    <th class="px-4 py-3 text-right w-12"></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for track <- Enum.sort_by(@active_project.project_tracks, & &1.position) do %>
                    <tr class="border-b border-gray-800/50 hover:bg-gray-800/30 transition-colors group">
                      <td class="px-4 py-3 text-gray-600 tabular-nums">
                        <%= track.position + 1 %>
                      </td>
                      <td class="px-4 py-3">
                        <span class="text-gray-200 font-medium">
                          <%= track.title ||
                            (track.audio_file && track.audio_file.title) ||
                            "Untitled" %>
                        </span>
                        <%= if track.audio_file && track.audio_file.artist do %>
                          <span class="text-gray-500 text-xs ml-2">
                            <%= track.audio_file.artist %>
                          </span>
                        <% end %>
                      </td>
                      <td class="px-4 py-3">
                        <%= if @track_override_id == track.id do %>
                          <!-- Inline type override dropdown -->
                          <form phx-change="override_track_type" class="flex items-center gap-2">
                            <input type="hidden" name="track-id" value={track.id} />
                            <select
                              name="type"
                              class="select select-xs select-bordered bg-gray-800 border-gray-600 text-gray-100"
                            >
                              <option value="full_track" selected={track.track_type == "full_track"}>
                                Full Track
                              </option>
                              <option value="loop" selected={track.track_type == "loop"}>Loop</option>
                              <option value="drum_loop" selected={track.track_type == "drum_loop"}>
                                Drum Loop
                              </option>
                              <option value="sample_loop" selected={track.track_type == "sample_loop"}>
                                Sample Loop
                              </option>
                            </select>
                            <button
                              type="button"
                              phx-click="cancel_track_override"
                              class="btn btn-xs btn-ghost text-gray-500"
                            >
                              ✕
                            </button>
                          </form>
                        <% else %>
                          <!-- Type badge -->
                          <% is_manual = get_in(track.metadata, ["manual"]) == true %>
                          <button
                            phx-click={if is_manual, do: nil, else: "set_track_override"}
                            phx-value-id={track.id}
                            class={[
                              badge_class(track.track_type),
                              "gap-1",
                              if(is_manual, do: "cursor-default opacity-80", else: "cursor-pointer")
                            ]}
                            title={
                              if is_manual,
                                do: "Manually set — click lock to re-classify automatically",
                                else: "Click to override type"
                            }
                          >
                            <%= if is_manual do %>
                              <svg
                                xmlns="http://www.w3.org/2000/svg"
                                class="h-2.5 w-2.5"
                                viewBox="0 0 20 20"
                                fill="currentColor"
                              >
                                <path
                                  fill-rule="evenodd"
                                  d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z"
                                  clip-rule="evenodd"
                                />
                              </svg>
                            <% end %>
                            <%= badge_label(track.track_type) %>
                            <%= if conf = get_in(track.metadata, ["confidence"]) do %>
                              <span class="opacity-70 text-xs"><%= round(conf * 100) %>%</span>
                            <% end %>
                          </button>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-gray-400 tabular-nums">
                        <%= format_duration(track.audio_file && track.audio_file.duration) %>
                      </td>
                      <td class="px-4 py-3 text-gray-400 tabular-nums">
                        <%= if track.audio_file && track.audio_file.bpm do %>
                          <%= :erlang.float_to_binary(track.audio_file.bpm, decimals: 0) %>
                        <% else %>
                          —
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-right">
                        <button
                          phx-click="remove_track"
                          phx-value-id={track.id}
                          data-confirm="Remove this track from the project?"
                          class="btn btn-xs btn-ghost text-gray-600 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
                        >
                          ✕
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        <% else %>
          <!-- No projects empty state -->
          <div class="flex-1 flex items-center justify-center">
            <div class="text-center">
              <h2 class="text-2xl font-semibold text-gray-200 mb-2">No Projects Yet</h2>
              <p class="text-gray-400 mb-6">Start a new project to begin arranging tracks.</p>
              <button phx-click="new_project" class="btn btn-primary">+ New Project</button>
            </div>
          </div>
        <% end %>
      </main>

      <!-- Import Tracks slide-over panel (right side) -->
      <div class={[
        "fixed inset-y-0 right-0 w-[480px] bg-gray-900 border-l border-gray-800 z-40",
        "flex flex-col shadow-2xl transform transition-transform duration-300 ease-in-out",
        if(@add_track_open, do: "translate-x-0", else: "translate-x-full")
      ]}>
        <%!-- Header --%>
        <div class="flex items-center justify-between px-5 py-4 border-b border-gray-800 flex-shrink-0">
          <h3 class="text-base font-semibold text-gray-100">Import Tracks</h3>
          <button
            phx-click="close_add_track"
            class="btn btn-sm btn-ghost text-gray-400 hover:text-gray-200"
          >
            ✕
          </button>
        </div>

        <%!-- Source tabs --%>
        <div class="flex border-b border-gray-800 px-5 flex-shrink-0">
          <button
            phx-click="set_import_source"
            phx-value-source="library"
            class={[
              "py-3 pr-5 text-sm font-medium border-b-2 -mb-px transition-colors",
              if(@import_source == :library,
                do: "border-primary text-primary",
                else: "border-transparent text-gray-400 hover:text-gray-200"
              )
            ]}
          >
            Library
          </button>
          <button
            phx-click="set_import_source"
            phx-value-source="crate"
            class={[
              "py-3 px-5 text-sm font-medium border-b-2 -mb-px transition-colors",
              if(@import_source == :crate,
                do: "border-primary text-primary",
                else: "border-transparent text-gray-400 hover:text-gray-200"
              )
            ]}
          >
            Crate
          </button>
        </div>

        <%!-- Search bar (library tab only) --%>
        <%= if @import_source == :library do %>
          <div class="px-5 py-3 border-b border-gray-800 flex-shrink-0">
            <form phx-change="search_library">
              <input
                type="search"
                name="query"
                value={@library_search}
                placeholder="Search by title or artist..."
                phx-debounce="300"
                class="input input-sm input-bordered bg-gray-800 border-gray-700 text-gray-100 w-full placeholder-gray-500"
              />
            </form>
          </div>
        <% end %>

        <%!-- Crate breadcrumb (when browsing a crate's tracks) --%>
        <%= if @import_source == :crate && @selected_crate_id do %>
          <% active_crate = Enum.find(@user_crates, & &1.id == @selected_crate_id) %>
          <div class="px-5 py-2 border-b border-gray-800 flex items-center gap-2 flex-shrink-0 text-sm">
            <button
              phx-click="back_to_crate_list"
              class="text-gray-400 hover:text-gray-200 flex items-center gap-1"
            >
              <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
              </svg>
              Crates
            </button>
            <span class="text-gray-600">/</span>
            <span class="text-gray-300 truncate">
              <%= (active_crate && (active_crate.name || active_crate.spotify_playlist_id)) || "Crate" %>
            </span>
          </div>
        <% end %>

        <%!-- Track/Crate list --%>
        <div class="flex-1 overflow-y-auto divide-y divide-gray-800/40 min-h-0">
          <%!-- Library track list --%>
          <%= if @import_source == :library do %>
            <%= if Enum.empty?(@library_tracks) do %>
              <div class="flex items-center justify-center h-32">
                <p class="text-gray-500 text-sm">
                  <%= if @library_search == "",
                    do: "No tracks in library",
                    else: "No results for \"#{@library_search}\"" %>
                </p>
              </div>
            <% else %>
              <%= for {lib_track, index} <- Enum.with_index(@library_tracks) do %>
                <% selected = MapSet.member?(@selected_track_ids, lib_track.id) %>
                <div
                  phx-click="toggle_track_selection"
                  phx-value-track-id={lib_track.id}
                  phx-value-index={index}
                  class={[
                    "flex items-center gap-3 px-5 py-3 cursor-pointer transition-colors select-none",
                    if(selected,
                      do: "bg-primary/10 hover:bg-primary/15",
                      else: "hover:bg-gray-800"
                    )
                  ]}
                >
                  <input
                    type="checkbox"
                    class="checkbox checkbox-primary checkbox-sm flex-shrink-0 pointer-events-none"
                    checked={selected}
                    readonly
                  />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm text-gray-200 font-medium truncate">
                      <%= lib_track.title || "Untitled" %>
                    </p>
                    <%= if lib_track.artist do %>
                      <p class="text-xs text-gray-500 truncate"><%= lib_track.artist %></p>
                    <% end %>
                  </div>
                  <div class="flex-shrink-0 text-right">
                    <p class="text-xs text-gray-500 tabular-nums">
                      <%= format_duration(lib_track.duration) %>
                    </p>
                    <%= if lib_track.bpm do %>
                      <p class="text-xs text-gray-600 tabular-nums">
                        <%= :erlang.float_to_binary(lib_track.bpm, decimals: 0) %> BPM
                      </p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            <% end %>
          <% end %>

          <%!-- Crate list (select which crate to browse) --%>
          <%= if @import_source == :crate && is_nil(@selected_crate_id) do %>
            <%= if Enum.empty?(@user_crates) do %>
              <div class="flex flex-col items-center justify-center h-32 gap-2">
                <p class="text-gray-500 text-sm">No crates found.</p>
                <a href="/crate" class="text-primary text-sm hover:underline">Open Crate Digger</a>
              </div>
            <% else %>
              <%= for crate <- @user_crates do %>
                <button
                  phx-click="select_crate_to_browse"
                  phx-value-crate-id={crate.id}
                  class="w-full text-left px-5 py-3 hover:bg-gray-800 transition-colors flex items-center justify-between gap-3"
                >
                  <div class="min-w-0">
                    <p class="text-sm text-gray-200 font-medium truncate">
                      <%= crate.name || crate.spotify_playlist_id || "Untitled Crate" %>
                    </p>
                    <p class="text-xs text-gray-500">
                      <%= length(crate.track_configs) %> track(s) in crate
                    </p>
                  </div>
                  <svg
                    class="w-4 h-4 text-gray-500 flex-shrink-0"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    stroke-width="2"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
                  </svg>
                </button>
              <% end %>
            <% end %>
          <% end %>

          <%!-- Crate track list (after selecting a crate) --%>
          <%= if @import_source == :crate && @selected_crate_id do %>
            <%= if Enum.empty?(@crate_matched_tracks) do %>
              <div class="flex flex-col items-center justify-center h-32 gap-1 px-6 text-center">
                <p class="text-gray-500 text-sm">No downloaded tracks from this crate.</p>
                <p class="text-xs text-gray-600">Download tracks first via the Crate Digger.</p>
              </div>
            <% else %>
              <%= for {crate_track, index} <- Enum.with_index(@crate_matched_tracks) do %>
                <% selected = MapSet.member?(@selected_track_ids, crate_track.id) %>
                <div
                  phx-click="toggle_track_selection"
                  phx-value-track-id={crate_track.id}
                  phx-value-index={index}
                  class={[
                    "flex items-center gap-3 px-5 py-3 cursor-pointer transition-colors select-none",
                    if(selected,
                      do: "bg-primary/10 hover:bg-primary/15",
                      else: "hover:bg-gray-800"
                    )
                  ]}
                >
                  <input
                    type="checkbox"
                    class="checkbox checkbox-primary checkbox-sm flex-shrink-0 pointer-events-none"
                    checked={selected}
                    readonly
                  />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm text-gray-200 font-medium truncate">
                      <%= crate_track.title || "Untitled" %>
                    </p>
                    <%= if crate_track.artist do %>
                      <p class="text-xs text-gray-500 truncate"><%= crate_track.artist %></p>
                    <% end %>
                  </div>
                  <div class="flex-shrink-0 text-right">
                    <p class="text-xs text-gray-500 tabular-nums">
                      <%= format_duration(crate_track.duration) %>
                    </p>
                    <%= if crate_track.bpm do %>
                      <p class="text-xs text-gray-600 tabular-nums">
                        <%= :erlang.float_to_binary(crate_track.bpm, decimals: 0) %> BPM
                      </p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            <% end %>
          <% end %>
        </div>

        <%!-- Footer action bar (shown when track list is visible) --%>
        <%= if @import_source == :library || (@import_source == :crate && @selected_crate_id) do %>
          <% selected_count = MapSet.size(@selected_track_ids) %>
          <div class="px-5 py-3 border-t border-gray-800 flex-shrink-0 flex items-center justify-between gap-3">
            <div class="flex items-center gap-3 text-sm">
              <span class="text-gray-400">
                <%= if selected_count == 0, do: "None selected", else: "#{selected_count} selected" %>
              </span>
              <button
                phx-click="select_all_tracks"
                class="text-xs text-gray-500 hover:text-gray-200 underline underline-offset-2"
              >
                Select all
              </button>
              <%= if selected_count > 0 do %>
                <button
                  phx-click="clear_selection"
                  class="text-xs text-gray-500 hover:text-gray-200 underline underline-offset-2"
                >
                  Clear
                </button>
              <% end %>
            </div>
            <button
              phx-click="add_selected_tracks"
              disabled={selected_count == 0}
              class={[
                "btn btn-sm btn-primary",
                if(selected_count == 0, do: "btn-disabled opacity-40", else: "")
              ]}
            >
              <%= cond do %>
                <% selected_count == 0 -> %>Add Tracks
                <% selected_count == 1 -> %>Add 1 Track
                <% true -> %>Add <%= selected_count %> Tracks
              <% end %>
            </button>
          </div>
        <% end %>
      </div>

      <%!-- Panel backdrop (mobile) --%>
      <%= if @add_track_open do %>
        <div
          class="fixed inset-0 bg-black/50 z-30 md:hidden"
          phx-click="close_add_track"
        />
      <% end %>

    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp resolve_user_id(%{id: id}, _session) when is_integer(id), do: id

  defp resolve_user_id(_, session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _} <- Accounts.get_user_by_session_token(token) do
      user.id
    else
      _ -> nil
    end
  end
end
