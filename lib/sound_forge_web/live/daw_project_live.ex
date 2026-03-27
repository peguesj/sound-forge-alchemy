defmodule SoundForgeWeb.Live.DawProjectLive do
  use SoundForgeWeb, :live_view

  alias SoundForge.DAW
  alias SoundForge.Music
  alias SoundForge.CrateDigger

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id
    projects = DAW.list_projects(user_id)
    active_project = List.first(projects)

    # Load full project with preloaded tracks
    active_project =
      if active_project, do: DAW.get_project!(active_project.id), else: nil

    {:ok,
     assign(socket,
       projects: projects,
       active_project: active_project,
       add_track_open: false,
       library_tracks: [],
       library_search: "",
       track_override_id: nil,
       import_crate_open: false,
       user_crates: [],
       page_title: "DAW"
     )}
  end

  @impl true
  def handle_params(%{"track_id" => track_id}, _uri, socket) do
    # Backward compat: /daw/:track_id just loads the DAW, ignoring track_id for now
    {:noreply, assign(socket, :requested_track_id, track_id)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp reload_project(socket, project_id) do
    project = DAW.get_project!(project_id)
    projects = DAW.list_projects(socket.assigns.current_user.id)
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

  defp scope(socket), do: %{user: socket.assigns.current_user}

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
    user_id = socket.assigns.current_user.id

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
        projects = DAW.list_projects(socket.assigns.current_user.id)
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
    {:noreply, assign(socket, add_track_open: true, library_tracks: library_tracks, library_search: "")}
  end

  def handle_event("close_add_track", _params, socket) do
    {:noreply, assign(socket, add_track_open: false)}
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

  def handle_event("add_track_from_library", %{"track-id" => track_id}, socket) do
    project = socket.assigns.active_project
    position = length(project.project_tracks)

    track = Music.get_track!(track_id)

    attrs = %{
      audio_file_id: track.id,
      title: track.title,
      position: position,
      track_type: "unknown"
    }

    case DAW.add_track(project.id, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> reload_project(project.id)
         |> assign(add_track_open: false)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add track")}
    end
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
  # Event handlers — crate import
  # ---------------------------------------------------------------------------

  def handle_event("open_import_crate", _params, socket) do
    user_id = socket.assigns.current_user.id
    crates = CrateDigger.list_crates(user_id)
    {:noreply, assign(socket, import_crate_open: true, user_crates: crates)}
  end

  def handle_event("close_import_crate", _params, socket) do
    {:noreply, assign(socket, import_crate_open: false)}
  end

  def handle_event("import_from_crate", %{"crate-id" => crate_id}, socket) do
    project = socket.assigns.active_project

    case DAW.import_from_crate(project.id, crate_id) do
      {:ok, %{imported: n, skipped: s}} ->
        {:noreply,
         socket
         |> reload_project(project.id)
         |> assign(import_crate_open: false)
         |> put_flash(:info, "Imported #{n} track(s), skipped #{s} duplicate(s)")}

      {:error, :crate_not_found} ->
        {:noreply, put_flash(socket, :error, "Crate not found")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not import from crate")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full min-h-screen bg-gray-950 text-gray-100 relative overflow-hidden">

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

      <!-- Add Track slide-over panel (right side) -->
      <div class={[
        "fixed inset-y-0 right-0 w-96 bg-gray-900 border-l border-gray-800 z-40",
        "flex flex-col shadow-2xl transform transition-transform duration-300 ease-in-out",
        if(@add_track_open, do: "translate-x-0", else: "translate-x-full")
      ]}>
        <div class="flex items-center justify-between px-5 py-4 border-b border-gray-800">
          <h3 class="text-base font-semibold text-gray-100">Add Track</h3>
          <button
            phx-click="close_add_track"
            class="btn btn-sm btn-ghost text-gray-400 hover:text-gray-200"
          >
            ✕
          </button>
        </div>

        <div class="px-5 py-3 border-b border-gray-800">
          <form phx-change="search_library">
            <input
              type="search"
              name="query"
              value={@library_search}
              placeholder="Search tracks..."
              phx-debounce="300"
              class="input input-sm input-bordered bg-gray-800 border-gray-700 text-gray-100 w-full placeholder-gray-500"
            />
          </form>
        </div>

        <div class="flex-1 overflow-y-auto divide-y divide-gray-800/50">
          <%= if Enum.empty?(@library_tracks) do %>
            <div class="flex items-center justify-center h-32">
              <p class="text-gray-500 text-sm">
                <%= if @library_search == "",
                  do: "No tracks in library",
                  else: "No results for \"#{@library_search}\"" %>
              </p>
            </div>
          <% else %>
            <%= for lib_track <- @library_tracks do %>
              <button
                phx-click="add_track_from_library"
                phx-value-track-id={lib_track.id}
                class="w-full text-left px-5 py-3 hover:bg-gray-800 transition-colors flex items-center justify-between gap-3"
              >
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
              </button>
            <% end %>
          <% end %>
        </div>
      </div>

      <!-- Add Track backdrop (mobile only) -->
      <%= if @add_track_open do %>
        <div
          class="fixed inset-0 bg-black/50 z-30 md:hidden"
          phx-click="close_add_track"
        />
      <% end %>

      <!-- Import from Crate modal -->
      <%= if @import_crate_open do %>
        <div class="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4">
          <div class="bg-gray-900 border border-gray-700 rounded-xl w-full max-w-md shadow-2xl">
            <div class="flex items-center justify-between px-6 py-4 border-b border-gray-800">
              <h3 class="text-base font-semibold text-gray-100">Import from Crate</h3>
              <button
                phx-click="close_import_crate"
                class="btn btn-sm btn-ghost text-gray-400 hover:text-gray-200"
              >
                ✕
              </button>
            </div>
            <div class="p-4 max-h-80 overflow-y-auto divide-y divide-gray-800/50">
              <%= if Enum.empty?(@user_crates) do %>
                <p class="text-sm text-gray-500 text-center py-8">
                  No crates found. Create one in Crate Digger first.
                </p>
              <% else %>
                <%= for crate <- @user_crates do %>
                  <button
                    phx-click="import_from_crate"
                    phx-value-crate-id={crate.id}
                    class="w-full text-left px-4 py-3 hover:bg-gray-800 transition-colors flex items-center justify-between gap-3"
                  >
                    <div>
                      <p class="text-sm text-gray-200 font-medium">
                        <%= crate.name || crate.spotify_playlist_id || "Untitled Crate" %>
                      </p>
                      <p class="text-xs text-gray-500">
                        <%= length(crate.track_configs) %> track(s)
                      </p>
                    </div>
                    <span class="badge badge-sm badge-ghost text-gray-400">Import</span>
                  </button>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

    </div>
    """
  end
end
