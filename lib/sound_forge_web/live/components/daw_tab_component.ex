defmodule SoundForgeWeb.Live.Components.DawTabComponent do
  @moduledoc """
  DAW editor component rendered inline within the dashboard.

  When no track is selected, renders a track picker grid.
  When a track is selected, renders the full DAW editor with per-stem
  waveforms, region-based operations, preview, and export.
  """
  use SoundForgeWeb, :live_component

  alias SoundForge.Music
  alias SoundForge.DAW
  alias SoundForgeWeb.Helpers.TrackHelpers
  alias SoundForge.Audio.AnalysisHelpers
  alias SoundForge.Audio.Prefetch
  alias SoundForge.Settings

  @operation_colors %{
    crop: "#3b82f6",
    trim: "#ef4444",
    fade_in: "#22c55e",
    fade_out: "#22c55e",
    split: "#eab308",
    gain: "#f97316"
  }

  # -- Lifecycle --

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:operation_colors, @operation_colors)
     |> assign(:track, nil)
     |> assign(:stems, [])
     |> assign(:stem_operations, %{})
     |> assign(:selected_operation, :crop)
     |> assign(:selected_stem_id, nil)
     |> assign(:previewing, false)
     |> assign(:export_status, nil)
     |> assign(:picker_tracks, [])
     |> assign(:initialized, false)
     |> assign(:snap_to_bar, false)
     |> assign(:structure_segments, [])
     |> assign(:bar_times, [])
     |> assign(:stem_mixer, %{})
     |> assign(:pipeline_status, track_pipeline_status(nil))}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, :current_scope, assigns[:current_scope])
    socket = assign(socket, :current_user_id, assigns[:current_user_id])
    socket = assign(socket, :id, assigns[:id])

    track_id = assigns[:track_id]

    if not socket.assigns.initialized do
      picker_tracks = TrackHelpers.list_user_tracks(assigns[:current_scope])
      socket = assign(socket, picker_tracks: picker_tracks, initialized: true)

      if track_id do
        {:ok, load_track(socket, track_id)}
      else
        {:ok, socket}
      end
    else
      # Handle track_id changes after init
      current_track_id = socket.assigns.track && socket.assigns.track.id

      if track_id && track_id != current_track_id do
        {:ok, load_track(socket, track_id)}
      else
        {:ok, socket}
      end
    end
  end

  defp load_track(socket, track_id) do
    user_id = socket.assigns[:current_user_id]

    try do
      track =
        Music.get_track!(track_id)
        |> SoundForge.Repo.preload([:stems, :analysis_results, :download_jobs])

      stems = track.stems

      stem_operations =
        Map.new(stems, fn stem ->
          ops = DAW.list_edit_operations(stem.id, user_id)
          {stem.id, ops}
        end)

      # Use prefetch cache for structure/bar data when available
      {structure_segments, bar_times} =
        case Prefetch.get_cached(track_id, :daw) do
          %{structure_segments: segs, bar_times: bars} ->
            {segs, bars}

          nil ->
            segs =
              case track.analysis_results do
                [result | _] -> AnalysisHelpers.structure_segments(result)
                _ -> []
              end

            bars =
              case track.analysis_results do
                [result | _] -> AnalysisHelpers.bar_times(result)
                _ -> []
              end

            {segs, bars}
        end

      stem_mixer =
        Map.new(stems, fn stem ->
          {stem.id, %{volume: 1.0, muted: false, solo: false, pan: 0.0}}
        end)

      # Verify the downloaded file actually exists on disk (DB may be stale)
      file_ok =
        case Music.get_download_path_validated(track.id) do
          {:ok, _path} -> true
          {:error, _} -> false
        end

      pipeline_status = track_pipeline_status(track, file_ok)

      socket
      |> assign(:track, track)
      |> assign(:stems, stems)
      |> assign(:stem_operations, stem_operations)
      |> assign(:structure_segments, structure_segments)
      |> assign(:bar_times, bar_times)
      |> assign(:stem_mixer, stem_mixer)
      |> assign(:pipeline_status, pipeline_status)
    rescue
      Ecto.NoResultsError ->
        put_flash(socket, :error, "Track not found")
    end
  end

  # -- Events --

  @impl true
  def handle_event("pick_track", %{"track-id" => track_id}, socket) do
    {:noreply, load_track(socket, track_id)}
  end

  @impl true
  def handle_event("verify_file", %{"track-id" => track_id}, socket) do
    track = SoundForge.Music.get_track!(track_id)
    file_exists = track.file_path && File.exists?(track.file_path)

    case SoundForge.Music.update_track(track, %{file_ok: file_exists}) do
      {:ok, t} -> {:noreply, assign(socket, :track, t)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("back_to_picker", _params, socket) do
    {:noreply,
     socket
     |> assign(:track, nil)
     |> assign(:stems, [])
     |> assign(:stem_operations, %{})
     |> assign(:selected_stem_id, nil)
     |> assign(:previewing, false)
     |> assign(:export_status, nil)
     |> assign(:structure_segments, [])
     |> assign(:bar_times, [])
     |> assign(:pipeline_status, track_pipeline_status(nil))}
  end

  # ---------------------------------------------------------------------------
  # Pipeline action events (DAW contextual actions)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("daw_download_track", %{"track-id" => track_id}, socket) do
    user_id = socket.assigns[:current_user_id]

    case dispatch_download(track_id, user_id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Download started")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not start download")}
    end
  end

  @impl true
  def handle_event("daw_analyze_track", %{"track-id" => track_id}, socket) do
    user_id = socket.assigns[:current_user_id]

    case dispatch_analysis(track_id, user_id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Analysis started")}

      {:error, :no_completed_download} ->
        {:noreply, put_flash(socket, :error, "Download the track before analyzing")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not start analysis")}
    end
  end

  @impl true
  def handle_event("daw_separate_stems", %{"track-id" => track_id}, socket) do
    user_id = socket.assigns[:current_user_id]

    case dispatch_stem_separation(track_id, user_id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Stem separation started")}

      {:error, :no_completed_download} ->
        {:noreply, put_flash(socket, :error, "Download the track before separating stems")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not start stem separation")}
    end
  end

  @impl true
  def handle_event("region_created", params, socket) do
    %{
      "stem_id" => stem_id,
      "start" => start_time,
      "end" => end_time
    } = params

    user_id = socket.assigns[:current_user_id]
    operation_type = socket.assigns.selected_operation
    existing_ops = Map.get(socket.assigns.stem_operations, stem_id, [])
    next_position = length(existing_ops)

    attrs = %{
      stem_id: stem_id,
      user_id: user_id,
      operation_type: operation_type,
      params: region_params(operation_type, start_time, end_time),
      position: next_position
    }

    case DAW.create_edit_operation(attrs) do
      {:ok, operation} ->
        updated_ops = existing_ops ++ [operation]
        stem_operations = Map.put(socket.assigns.stem_operations, stem_id, updated_ops)

        {:noreply,
         socket
         |> assign(:stem_operations, stem_operations)
         |> push_event("operation_created", %{
           stem_id: stem_id,
           operation_id: operation.id,
           operation_type: to_string(operation_type),
           region_id: params["region_id"],
           params: operation.params
         })}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create operation")}
    end
  end

  @impl true
  def handle_event("region_updated", params, socket) do
    %{
      "operation_id" => operation_id,
      "start" => start_time,
      "end" => end_time
    } = params

    try do
      operation = DAW.get_edit_operation!(operation_id)

      updated_params =
        Map.merge(operation.params, region_params(operation.operation_type, start_time, end_time))

      case DAW.update_edit_operation(operation, %{params: updated_params}) do
        {:ok, updated_op} ->
          stem_id = updated_op.stem_id

          stem_operations =
            Map.update!(socket.assigns.stem_operations, stem_id, fn ops ->
              Enum.map(ops, fn op ->
                if op.id == updated_op.id, do: updated_op, else: op
              end)
            end)

          {:noreply, assign(socket, :stem_operations, stem_operations)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update operation")}
      end
    rescue
      Ecto.NoResultsError ->
        {:noreply, put_flash(socket, :error, "Operation not found")}
    end
  end

  @impl true
  def handle_event("region_removed", %{"operation_id" => operation_id}, socket) do
    try do
      operation = DAW.get_edit_operation!(operation_id)

      case DAW.delete_edit_operation(operation) do
        {:ok, deleted_op} ->
          stem_id = deleted_op.stem_id

          stem_operations =
            Map.update!(socket.assigns.stem_operations, stem_id, fn ops ->
              Enum.reject(ops, &(&1.id == deleted_op.id))
            end)

          {:noreply, assign(socket, :stem_operations, stem_operations)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to remove operation")}
      end
    rescue
      Ecto.NoResultsError ->
        {:noreply, put_flash(socket, :error, "Operation not found")}
    end
  end

  @valid_operations ~w(crop trim fade_in fade_out split gain pitch_shift time_stretch)a

  @impl true
  def handle_event("select_operation", %{"type" => type}, socket) do
    operation =
      try do
        atom = String.to_existing_atom(type)
        if atom in @valid_operations, do: atom, else: :crop
      rescue
        ArgumentError -> :crop
      end

    {:noreply, assign(socket, :selected_operation, operation)}
  end

  @impl true
  def handle_event("toggle_snap", _params, socket) do
    {:noreply, assign(socket, :snap_to_bar, !socket.assigns.snap_to_bar)}
  end

  @impl true
  def handle_event("select_region", %{"start_ms" => start_ms, "end_ms" => end_ms}, socket) do
    {:noreply,
     push_event(socket, "set_selection", %{start_ms: start_ms, end_ms: end_ms})}
  end

  @impl true
  def handle_event("apply_operation", %{"stem_id" => stem_id}, socket) do
    user_id = socket.assigns[:current_user_id]
    operation_type = socket.assigns.selected_operation

    if operation_type == :split do
      {:noreply, push_event(socket, "request_cursor_for_split", %{stem_id: stem_id})}
    else
      existing_ops = Map.get(socket.assigns.stem_operations, stem_id, [])
      next_position = length(existing_ops)

      attrs = %{
        stem_id: stem_id,
        user_id: user_id,
        operation_type: operation_type,
        params: default_params(operation_type),
        position: next_position
      }

      case DAW.create_edit_operation(attrs) do
        {:ok, operation} ->
          updated_ops = existing_ops ++ [operation]
          stem_operations = Map.put(socket.assigns.stem_operations, stem_id, updated_ops)

          {:noreply,
           socket
           |> assign(:stem_operations, stem_operations)
           |> push_event("add_region", %{
             stem_id: stem_id,
             operation_id: operation.id,
             operation_type: to_string(operation_type),
             color: Map.get(@operation_colors, operation_type, "#6b7280"),
             params: params_with_seconds(operation.params)
           })}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to apply operation")}
      end
    end
  end

  @impl true
  def handle_event(
        "apply_split",
        %{"stem_id" => stem_id, "cursor_position" => cursor_position},
        socket
      ) do
    user_id = socket.assigns[:current_user_id]
    existing_ops = Map.get(socket.assigns.stem_operations, stem_id, [])
    next_position = length(existing_ops)
    position_ms = round(cursor_position * 1000)

    attrs = %{
      stem_id: stem_id,
      user_id: user_id,
      operation_type: :split,
      params: %{"position_ms" => position_ms, "position_sec" => cursor_position},
      position: next_position
    }

    case DAW.create_edit_operation(attrs) do
      {:ok, operation} ->
        updated_ops = existing_ops ++ [operation]
        stem_operations = Map.put(socket.assigns.stem_operations, stem_id, updated_ops)

        {:noreply,
         socket
         |> assign(:stem_operations, stem_operations)
         |> push_event("add_split_marker", %{
           stem_id: stem_id,
           operation_id: operation.id,
           position_sec: cursor_position,
           color: Map.get(@operation_colors, :split, "#eab308")
         })}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create split")}
    end
  end

  @impl true
  def handle_event(
        "split_marker_moved",
        %{"operation_id" => operation_id, "position_sec" => position_sec},
        socket
      ) do
    try do
      operation = DAW.get_edit_operation!(operation_id)
      position_ms = round(position_sec * 1000)

      case DAW.update_edit_operation(operation, %{
             params: %{"position_ms" => position_ms, "position_sec" => position_sec}
           }) do
        {:ok, updated_op} ->
          stem_id = updated_op.stem_id

          stem_operations =
            Map.update!(socket.assigns.stem_operations, stem_id, fn ops ->
              Enum.map(ops, fn op ->
                if op.id == updated_op.id, do: updated_op, else: op
              end)
            end)

          {:noreply, assign(socket, :stem_operations, stem_operations)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update split position")}
      end
    rescue
      Ecto.NoResultsError ->
        {:noreply, put_flash(socket, :error, "Split operation not found")}
    end
  end

  @impl true
  def handle_event("undo_last", %{"stem_id" => stem_id}, socket) do
    existing_ops = Map.get(socket.assigns.stem_operations, stem_id, [])

    case List.last(existing_ops) do
      nil ->
        {:noreply, put_flash(socket, :info, "Nothing to undo")}

      last_op ->
        case DAW.delete_edit_operation(last_op) do
          {:ok, _} ->
            updated_ops = List.delete_at(existing_ops, -1)
            stem_operations = Map.put(socket.assigns.stem_operations, stem_id, updated_ops)

            {:noreply,
             socket
             |> assign(:stem_operations, stem_operations)
             |> push_event("remove_region", %{
               stem_id: stem_id,
               operation_id: last_op.id
             })}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to undo")}
        end
    end
  end

  @impl true
  def handle_event("select_stem", %{"stem-id" => stem_id}, socket) do
    {:noreply, assign(socket, :selected_stem_id, stem_id)}
  end

  @impl true
  def handle_event("toggle_preview", _params, socket) do
    new_state = !socket.assigns.previewing

    socket =
      socket
      |> assign(:previewing, new_state)
      |> push_event("daw_preview", %{
        playing: new_state,
        operations: encode_all_operations(socket.assigns.stem_operations)
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_preview", _params, socket) do
    socket =
      socket
      |> assign(:previewing, false)
      |> push_event("daw_preview", %{playing: false})

    {:noreply, socket}
  end

  @impl true
  def handle_event("export_stem", %{"stem_id" => stem_id}, socket) do
    socket =
      socket
      |> assign(:export_status, "starting")
      |> push_event("export_stem", %{stem_id: stem_id})

    {:noreply, socket}
  end

  @impl true
  def handle_event("export_progress", %{"status" => status} = params, socket) do
    socket = assign(socket, :export_status, status)

    socket =
      case status do
        "complete" ->
          stem_id = params["stem_id"]

          if stem_id do
            track = Music.get_track!(socket.assigns.track.id) |> SoundForge.Repo.preload([:stems, :analysis_results])
            assign(socket, :track, track) |> assign(:stems, track.stems)
          else
            socket
          end

        "error" ->
          put_flash(socket, :error, params["message"] || "Export failed")

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # Stem Arranger (Story 3.2)

  @impl true
  def handle_event("toggle_arrangement_block", %{"stem_type" => stem_type, "start_sec" => start_sec, "end_sec" => end_sec}, socket) do
    track = socket.assigns.track
    if is_nil(track), do: {:noreply, socket}

    arrangement = track.stem_arrangement || %{}
    regions = Map.get(arrangement, stem_type, [])

    # Toggle muted for any existing region that overlaps, or add a muted block
    updated_regions =
      if Enum.any?(regions, &(&1["start_sec"] == start_sec && &1["end_sec"] == end_sec)) do
        Enum.map(regions, fn r ->
          if r["start_sec"] == start_sec && r["end_sec"] == end_sec do
            Map.put(r, "muted", !r["muted"])
          else
            r
          end
        end)
      else
        [%{"start_sec" => start_sec, "end_sec" => end_sec, "muted" => true} | regions]
      end

    updated_arrangement = Map.put(arrangement, stem_type, updated_regions)

    case Music.update_track(track, %{stem_arrangement: updated_arrangement}) do
      {:ok, updated_track} ->
        {:noreply,
         socket
         |> assign(:track, updated_track)
         |> push_event("set_arrangement", %{arrangement: updated_arrangement})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("update_stem_mix", %{"stem_id" => stem_id} = params, socket) do
    mixer = socket.assigns.stem_mixer
    current = Map.get(mixer, stem_id, %{volume: 1.0, muted: false, solo: false, pan: 0.0})

    updated =
      current
      |> maybe_put(:volume, params["volume"] && String.to_float(params["volume"]))
      |> maybe_put(:muted, params["muted"] && params["muted"] == "true")
      |> maybe_put(:solo, params["solo"] && params["solo"] == "true")
      |> maybe_put(:pan, params["pan"] && String.to_float(params["pan"]))

    new_mixer = Map.put(mixer, stem_id, updated)
    {:noreply,
     socket
     |> assign(:stem_mixer, new_mixer)
     |> push_event("stem_mix_update", %{stem_id: stem_id, mix: updated})}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # -- Template --

  @impl true
  def render(assigns) do
    ~H"""
    <div id="daw-tab" phx-target={@myself} class="flex-1 min-w-0 overflow-hidden">
      <%= if @track do %>
        <div id="daw-preview-container" phx-hook="DawPreview" class="text-white flex-1 min-w-0 overflow-hidden">
          <%!-- Header --%>
          <div class="bg-gray-800 border-b border-gray-700 px-6 py-4">
            <div class="flex items-center gap-4">
              <button
                phx-click="back_to_picker"
                phx-target={@myself}
                class="text-gray-400 hover:text-white transition-colors"
                aria-label="Back to track picker"
              >
                <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
                </svg>
              </button>

              <button
                phx-click="toggle_preview"
                phx-target={@myself}
                class={"w-10 h-10 rounded-full flex items-center justify-center transition-colors " <>
                  if(@previewing, do: "bg-red-600 hover:bg-red-500", else: "bg-green-600 hover:bg-green-500")}
                aria-label={if @previewing, do: "Stop preview", else: "Play preview"}
              >
                <svg :if={!@previewing} class="w-5 h-5 ml-0.5 text-white" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M8 5v14l11-7z" />
                </svg>
                <svg :if={@previewing} class="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 24 24">
                  <rect x="6" y="4" width="4" height="16" />
                  <rect x="14" y="4" width="4" height="16" />
                </svg>
              </button>

              <div>
                <h1 class="text-xl font-bold text-white">DAW Editor</h1>
                <p class="text-sm text-gray-400">
                  {@track.title}
                  <span :if={@track.artist} class="text-gray-500">- {@track.artist}</span>
                </p>
                <%!-- Pipeline status badges --%>
                <div class="flex flex-wrap gap-1.5 mt-1.5">
                  <span :if={@pipeline_status.on_spotify} class="badge badge-sm bg-purple-600 text-white border-0">Spotify</span>
                  <span :if={@pipeline_status.downloaded and @pipeline_status.file_ok} class="badge badge-sm bg-blue-600 text-white border-0">Downloaded</span>
                  <span :if={@pipeline_status.downloaded and not @pipeline_status.file_ok} class="badge badge-sm bg-amber-600 text-white border-0" title="Audio file missing from disk">File Missing</span>
                  <span :if={@pipeline_status.analyzed and @pipeline_status.file_ok} class="badge badge-sm bg-teal-600 text-white border-0">Analyzed</span>
                  <span :if={@pipeline_status.processed} class="badge badge-sm bg-green-600 text-white border-0">Processed</span>
                </div>
              </div>

              <%!-- Global Operation Selector --%>
              <div class="ml-auto flex items-center gap-2">
                <%!-- Import Stem from Library (US-B07) --%>
                <button
                  phx-click="verify_file"
                  phx-target={@myself}
                  phx-value-track-id={@track && @track.id}
                  class="btn btn-xs btn-outline"
                >
                  Verify File
                </button>
                <button
                  phx-click="toggle_daw_library"
                  class="flex items-center gap-1 px-2 py-1 text-xs rounded bg-violet-900/40 hover:bg-violet-900/70 text-violet-300 transition-colors"
                  title="Import stem from library"
                >
                  <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                      d="M8 6H21M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01" />
                  </svg>
                  Library
                </button>
                <div class="w-px h-5 bg-gray-700"></div>
                <button phx-click="toggle_snap" phx-target={@myself}
                        class={"px-2 py-1 text-xs rounded " <> if(@snap_to_bar, do: "bg-purple-600 text-white", else: "bg-gray-700 text-gray-400")}>
                  Snap to Bar
                </button>
                <div class="w-px h-5 bg-gray-700 mx-1"></div>
                <span class="text-xs text-gray-500 mr-2">Tool:</span>
                <button
                  :for={op <- [:crop, :trim, :fade_in, :fade_out, :split, :gain, :pitch_shift, :time_stretch]}
                  phx-click="select_operation"
                  phx-target={@myself}
                  phx-value-type={op}
                  aria-label={"Select #{operation_label(op)} tool"}
                  aria-pressed={to_string(@selected_operation == op)}
                  class={"px-3 py-1.5 rounded text-xs font-medium transition-colors " <>
                    if(@selected_operation == op,
                      do: "ring-2 ring-offset-1 ring-offset-gray-800 " <> operation_button_active(op),
                      else: "bg-gray-700 text-gray-300 hover:bg-gray-600")}
                >
                  {operation_label(op)}
                </button>
              </div>
            </div>
          </div>

          <%!-- Time Grid Ruler --%>
          <div :if={@stems != []} class="px-6 pt-4 pb-0">
            <div
              id="daw-time-grid"
              class="relative h-7 bg-gray-900/70 rounded-t border-b border-gray-700/50 overflow-hidden"
              style="font-family: 'JetBrains Mono', 'SF Mono', 'Fira Code', monospace;"
            >
              <%!-- Time markers rendered via JS or statically --%>
              <div class="absolute inset-0 flex items-end">
                <%= for i <- time_grid_markers(get_track_duration(assigns)) do %>
                  <div
                    class="absolute bottom-0 flex flex-col items-center"
                    style={"left: #{i.percent}%"}
                  >
                    <span class="text-[9px] text-gray-500 mb-0.5 -translate-x-1/2">
                      {i.label}
                    </span>
                    <div class={"w-px bg-gray-700 " <> if(i.major, do: "h-3", else: "h-1.5")}></div>
                  </div>
                <% end %>
              </div>
              <%!-- Playback position indicator --%>
              <div
                id="daw-time-cursor"
                class="absolute top-0 bottom-0 w-0.5 bg-green-500 z-10 transition-all pointer-events-none"
                style="left: 0%;"
              >
                <div class="w-2 h-2 bg-green-500 rounded-full -translate-x-[3px] -translate-y-0.5"></div>
              </div>
            </div>
          </div>

          <%!-- Stem Tracks --%>
          <div class="p-6 pt-0 space-y-4">
            <%!-- Contextual pipeline action panel (shown only when no stems) --%>
            <div :if={@stems == []} class="text-center py-20 text-gray-500">
              <p class="text-lg font-medium text-gray-400">No stems available for this track.</p>
              <p class="text-sm mt-2 mb-6">Complete the pipeline steps below to prepare this track for editing.</p>

              <%!-- File missing warning --%>
              <div
                :if={@pipeline_status.downloaded and not @pipeline_status.file_ok}
                class="mx-auto mb-5 max-w-sm bg-amber-950/60 border border-amber-500/40 rounded-lg px-4 py-3 text-amber-300 text-sm text-left"
              >
                <p class="font-medium mb-0.5">Audio file not found on disk</p>
                <p class="text-xs text-amber-400/80">The download record exists but the file could not be located. Re-download to restore it.</p>
              </div>

              <div class="flex flex-col items-center gap-3 mt-4">
                <%!-- Step 1: Download / Re-download --%>
                <div :if={not @pipeline_status.downloaded or not @pipeline_status.file_ok} class="w-full max-w-sm">
                  <button
                    phx-click="daw_download_track"
                    phx-target={@myself}
                    phx-value-track-id={@track.id}
                    class="btn btn-sm btn-primary w-full"
                  >
                    <%= if @pipeline_status.downloaded and not @pipeline_status.file_ok, do: "Re-download Track", else: "Download Track" %>
                  </button>
                  <p class="text-xs text-gray-600 mt-1">
                    <%= if @pipeline_status.downloaded and not @pipeline_status.file_ok do %>
                      Fetch a fresh copy of the audio file
                    <% else %>
                      Fetch the audio file from Spotify
                    <% end %>
                  </p>
                </div>

                <%!-- Step 2: Analyze (only shown if file is present and not yet analyzed) --%>
                <div :if={@pipeline_status.downloaded and @pipeline_status.file_ok and not @pipeline_status.analyzed} class="w-full max-w-sm">
                  <button
                    phx-click="daw_analyze_track"
                    phx-target={@myself}
                    phx-value-track-id={@track.id}
                    class="btn btn-sm btn-secondary w-full"
                  >
                    Analyze Track
                  </button>
                  <p class="text-xs text-gray-600 mt-1">Detect BPM, key, and structure</p>
                </div>

                <%!-- Step 3: Separate stems (only shown if file is present and not yet processed) --%>
                <div :if={@pipeline_status.downloaded and @pipeline_status.file_ok and not @pipeline_status.processed} class="w-full max-w-sm">
                  <button
                    phx-click="daw_separate_stems"
                    phx-target={@myself}
                    phx-value-track-id={@track.id}
                    class="btn btn-sm btn-accent w-full"
                  >
                    Separate Stems
                  </button>
                  <p class="text-xs text-gray-600 mt-1">Split into vocals, drums, bass, and more</p>
                </div>
              </div>
            </div>

            <div
              :for={stem <- @stems}
              class={"bg-gray-800 rounded-lg border transition-colors " <>
                if(@selected_stem_id == stem.id,
                  do: "border-purple-500",
                  else: "border-gray-700 hover:border-gray-600")}
              phx-click="select_stem"
              phx-target={@myself}
              phx-value-stem-id={stem.id}
            >
              <%!-- Stem Header --%>
              <div class="flex flex-col gap-1.5 px-4 py-3 border-b border-gray-700/50">
                <div class="flex items-center gap-3">
                  <span class={"text-sm font-semibold w-24 shrink-0 " <> stem_color(stem.stem_type)}>
                    {stem_label(stem.stem_type)}
                  </span>
                  <%!-- Mixer controls: Mute / Solo / Volume / Pan --%>
                  <div class="flex items-center gap-2">
                    <%!-- Mute --%>
                    <button
                      phx-click="update_stem_mix"
                      phx-target={@myself}
                      phx-value-stem_id={stem.id}
                      phx-value-muted={to_string(!(Map.get(@stem_mixer, stem.id, %{muted: false}).muted))}
                      title="Mute"
                      class={[
                        "text-[10px] font-bold px-1.5 py-0.5 rounded transition-colors",
                        if(Map.get(@stem_mixer, stem.id, %{muted: false}).muted,
                          do: "bg-yellow-500 text-gray-900",
                          else: "bg-gray-700 text-gray-400 hover:bg-gray-600")
                      ]}
                    >M</button>
                    <%!-- Solo --%>
                    <button
                      phx-click="update_stem_mix"
                      phx-target={@myself}
                      phx-value-stem_id={stem.id}
                      phx-value-solo={to_string(!(Map.get(@stem_mixer, stem.id, %{solo: false}).solo))}
                      title="Solo"
                      class={[
                        "text-[10px] font-bold px-1.5 py-0.5 rounded transition-colors",
                        if(Map.get(@stem_mixer, stem.id, %{solo: false}).solo,
                          do: "bg-green-500 text-gray-900",
                          else: "bg-gray-700 text-gray-400 hover:bg-gray-600")
                      ]}
                    >S</button>
                    <%!-- Volume --%>
                    <div class="flex items-center gap-1">
                      <span class="text-[9px] text-gray-500 shrink-0">VOL</span>
                      <form phx-change="update_stem_mix" phx-target={@myself} class="flex items-center">
                        <input type="hidden" name="stem_id" value={stem.id} />
                        <input
                          type="range" name="volume"
                          min="0" max="1" step="0.01"
                          value={Map.get(@stem_mixer, stem.id, %{volume: 1.0}).volume}
                          class="w-20 h-1 accent-purple-500 cursor-pointer"
                          title={"Volume: #{round(Map.get(@stem_mixer, stem.id, %{volume: 1.0}).volume * 100)}%"}
                        />
                      </form>
                    </div>
                    <%!-- Pan/Balance --%>
                    <div class="flex items-center gap-1">
                      <span class="text-[9px] text-gray-500 shrink-0">PAN</span>
                      <form phx-change="update_stem_mix" phx-target={@myself} class="flex items-center">
                        <input type="hidden" name="stem_id" value={stem.id} />
                        <input
                          type="range" name="pan"
                          min="-1" max="1" step="0.01"
                          value={Map.get(@stem_mixer, stem.id, %{pan: 0.0}).pan}
                          class="w-16 h-1 accent-indigo-400 cursor-pointer"
                          title={"Pan: #{Map.get(@stem_mixer, stem.id, %{pan: 0.0}).pan}"}
                        />
                      </form>
                    </div>
                  </div>
                  <span class="text-xs bg-gray-700 text-gray-300 px-2 py-0.5 rounded-full ml-auto">
                    {length(Map.get(@stem_operations, stem.id, []))} ops
                  </span>
                </div>
                <div class="flex items-center gap-1 justify-end">
                  <button
                    :for={op <- [:crop, :trim, :fade_in, :fade_out, :split, :gain, :pitch_shift, :time_stretch]}
                    phx-click="apply_operation"
                    phx-target={@myself}
                    phx-value-stem_id={stem.id}
                    title={"Apply #{operation_label(op)} to #{stem_label(stem.stem_type)}"}
                    class={"px-2 py-1 rounded text-xs transition-colors " <>
                      if(@selected_operation == op,
                        do: operation_button_active(op),
                        else: "bg-gray-700/50 text-gray-500 hover:bg-gray-700 hover:text-gray-300")}
                  >
                    {operation_icon(op)}
                  </button>
                  <div class="w-px h-5 bg-gray-700 mx-1"></div>
                  <button
                    phx-click="undo_last"
                    phx-target={@myself}
                    phx-value-stem_id={stem.id}
                    title="Undo last operation"
                    class="px-2 py-1 rounded text-xs bg-gray-700/50 text-gray-400 hover:bg-gray-700 hover:text-white transition-colors"
                  >
                    Undo
                  </button>
                </div>
              </div>

              <%!-- Waveform Container --%>
              <div
                id={"daw-stem-#{stem.id}"}
                phx-hook="DawEditor"
                phx-update="ignore"
                data-stem-id={stem.id}
                data-stem-type={stem.stem_type}
                data-track-id={@track && @track.id}
                data-stem-url={stem_audio_url(stem)}
                data-operations={Jason.encode!(encode_operations(Map.get(@stem_operations, stem.id, [])))}
                data-operation-colors={Jason.encode!(@operation_colors)}
                data-structure={Jason.encode!(@structure_segments || [])}
                data-bar-times={Jason.encode!(@bar_times || [])}
                class="px-4 py-3"
              >
                <div class="h-24 rounded bg-gray-900/50 flex items-center justify-center">
                  <span class="text-sm text-gray-600">Loading waveform...</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Stem Arranger Grid (Story 3.2) --%>
        <div :if={@stems != []} class="px-6 py-4 border-t border-gray-700">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-semibold text-gray-300">Stem Arranger</h3>
            <span class="text-xs text-gray-500">Click a block to mute/unmute that section</span>
          </div>
          <div
            id={"arrangement-grid-#{@track && @track.id}"}
            phx-hook="ArrangementGrid"
            phx-target={@myself}
            data-stems={Jason.encode!(Enum.map(@stems, fn s ->
              %{id: s.id, stem_type: s.stem_type, label: String.capitalize(to_string(s.stem_type)),
                color: stem_hex_color(s.stem_type)}
            end))}
            data-arrangement={Jason.encode!((@track && @track.stem_arrangement) || %{})}
            data-duration-sec={(@track && @track.duration) || 120}
            data-bpm={(@track && @track.bpm) || 120}
            class="overflow-x-auto"
          >
          </div>
        </div>
      <% else %>
        <%!-- Track Picker Grid --%>
        <div class="p-6">
          <div class="mb-6">
            <h2 class="text-xl font-bold text-white mb-1">DAW Editor</h2>
            <p class="text-sm text-gray-400">Select a track below to start editing stems</p>
          </div>

          <div :if={@picker_tracks == []} class="flex flex-col items-center justify-center py-32 text-center">
            <div class="w-16 h-16 rounded-full bg-gray-800 flex items-center justify-center mb-4">
              <svg class="w-8 h-8 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 9l10.5-3m0 6.553v3.75a2.25 2.25 0 01-1.632 2.163l-1.32.377a1.803 1.803 0 11-.99-3.467l2.31-.66a2.25 2.25 0 001.632-2.163zm0 0V2.25L9 5.25v10.303m0 0v3.75a2.25 2.25 0 01-1.632 2.163l-1.32.377a1.803 1.803 0 01-.99-3.467l2.31-.66A2.25 2.25 0 009 15.553z" />
              </svg>
            </div>
            <h3 class="text-lg font-semibold text-gray-200 mb-2">No tracks in your library</h3>
            <p class="text-sm text-gray-500 mb-6 max-w-xs">Add tracks from Spotify or upload audio files, then come back here to edit stems.</p>
            <button
              phx-click="toggle_daw_library"
              class="btn btn-sm btn-outline border-violet-600 text-violet-400 hover:bg-violet-600 hover:text-white"
            >
              Open Track Library
            </button>
          </div>

          <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
            <button
              :for={track <- @picker_tracks}
              phx-click="pick_track"
              phx-target={@myself}
              phx-value-track-id={track.id}
              class="group text-left bg-gray-800 rounded-lg border border-gray-700 hover:border-purple-500 hover:bg-gray-750 transition-all p-3"
            >
              <div class="aspect-square bg-gray-900 rounded-md overflow-hidden mb-2 relative">
                <div class="w-full h-full flex items-center justify-center text-gray-600 absolute inset-0">
                  <svg class="w-10 h-10" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3" />
                  </svg>
                </div>
                <img
                  :if={track.album_art_url && track.album_art_url != ""}
                  src={track.album_art_url}
                  class="w-full h-full object-cover relative z-10"
                  alt={track.title}
                  loading="lazy"
                  onerror="this.style.display='none'"
                />
              </div>
              <p class="text-sm text-white font-medium truncate group-hover:text-purple-300 transition-colors">
                {track.title}
              </p>
              <p :if={track.artist} class="text-xs text-gray-500 truncate">{track.artist}</p>
              <div class="flex items-center gap-1 mt-1">
                <span
                  :if={has_stems?(track)}
                  class="text-[10px] px-1.5 py-0.5 rounded bg-green-900/40 text-green-400 font-medium"
                >
                  Stems
                </span>
              </div>
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # -- Private Helpers --

  @stem_hex_colors %{
    "vocals" => "#6d28d9",
    "drums" => "#dc2626",
    "bass" => "#2563eb",
    "other" => "#059669",
    "piano" => "#d97706",
    "guitar" => "#db2777",
    "electric_guitar" => "#db2777",
    "acoustic_guitar" => "#92400e",
    "strings" => "#0891b2",
    "wind" => "#065f46",
    "synth" => "#7c3aed"
  }

  defp stem_hex_color(stem_type) do
    Map.get(@stem_hex_colors, to_string(stem_type), "#6b7280")
  end

  defp has_stems?(track) do
    case track do
      %{stems: stems} when is_list(stems) and stems != [] -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  # ---------------------------------------------------------------------------
  # Pipeline status helpers
  # ---------------------------------------------------------------------------

  defp track_pipeline_status(track, file_ok \\ true)

  defp track_pipeline_status(nil, _file_ok) do
    %{on_spotify: false, downloaded: false, file_ok: true, analyzed: false, processed: false}
  end

  defp track_pipeline_status(track, file_ok) do
    on_spotify = not is_nil(track.spotify_url)

    downloaded =
      track.download_status == "completed" or
        (is_list(track.download_jobs) and
           Enum.any?(track.download_jobs, &(&1.status == :completed)))

    analyzed =
      not is_nil(track.bpm) or
        (is_list(track.analysis_results) and track.analysis_results != [])

    processed = is_list(track.stems) and track.stems != []

    # file_ok is only meaningful when downloaded; if not downloaded, it's N/A (true)
    effective_file_ok = if downloaded, do: file_ok, else: true

    %{
      on_spotify: on_spotify,
      downloaded: downloaded,
      file_ok: effective_file_ok,
      analyzed: analyzed,
      processed: processed
    }
  end

  defp dispatch_download(track_id, user_id) do
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

  defp dispatch_analysis(track_id, user_id) do
    with {:ok, file_path} <- Music.get_download_path_validated(track_id),
         {:ok, job} <- Music.create_analysis_job(%{track_id: track_id, status: :queued}) do
      %{
        "track_id" => track_id,
        "job_id" => job.id,
        "file_path" => file_path,
        "features" => Settings.get(user_id, :analysis_features)
      }
      |> SoundForge.Jobs.AnalysisWorker.new()
      |> Oban.insert()
    end
  end

  defp dispatch_stem_separation(track_id, user_id) do
    model = Settings.get(user_id, :demucs_model)

    with {:ok, file_path} <- Music.get_download_path_validated(track_id),
         {:ok, job} <-
           Music.create_processing_job(%{
             track_id: track_id,
             model: model,
             status: :queued,
             engine: "demucs",
             preview: false
           }),
         {:ok, _oban_job} <-
           (%{
              "track_id" => track_id,
              "job_id" => job.id,
              "file_path" => file_path,
              "model" => model,
              "engine" => "demucs",
              "preview" => false,
              "lalalai_mode" => "stem_separator",
              "multistem_stems" => [],
              "noise_level" => 0,
              "voice_pack_id" => nil,
              "accent" => 0.5,
              "dereverb" => false
            }
            |> SoundForge.Jobs.ProcessingWorker.new()
            |> Oban.insert()) do
      {:ok, job}
    end
  end

  defp encode_all_operations(stem_operations) do
    Map.new(stem_operations, fn {stem_id, ops} ->
      encoded =
        Enum.map(ops, fn op ->
          %{
            type: to_string(op.operation_type),
            params: op.params,
            position: op.position
          }
        end)

      {stem_id, encoded}
    end)
  end

  defp stem_audio_url(stem) do
    relative = make_relative_path(stem.file_path)
    "/files/#{relative}"
  end

  defp make_relative_path(nil), do: ""

  defp make_relative_path(path) do
    base = SoundForge.Storage.base_path() |> Path.expand()
    cwd_base = Path.join(File.cwd!(), SoundForge.Storage.base_path()) |> Path.expand()

    demucs_base =
      Application.get_env(:sound_forge, :demucs_output_dir, "/tmp/demucs") |> Path.expand()

    expanded = Path.expand(path)

    cond do
      String.starts_with?(expanded, cwd_base <> "/") ->
        String.replace_prefix(expanded, cwd_base <> "/", "")

      String.starts_with?(expanded, base <> "/") ->
        String.replace_prefix(expanded, base <> "/", "")

      String.starts_with?(expanded, demucs_base <> "/") ->
        String.replace_prefix(expanded, demucs_base <> "/", "")

      true ->
        path
    end
  end

  defp encode_operations(operations) do
    Enum.map(operations, fn op ->
      op_type = to_string(op.operation_type)

      encoded_params =
        if op_type == "split" do
          pos_sec =
            op.params["position_sec"] ||
              ms_to_seconds(op.params["position_ms"]) ||
              op.params["start"] ||
              5.0

          Map.merge(op.params, %{"position_sec" => pos_sec})
        else
          start_s = ms_to_seconds(op.params["start_ms"]) || op.params["start"] || 0
          end_s = ms_to_seconds(op.params["end_ms"]) || op.params["end"] || 5
          Map.merge(op.params, %{"start" => start_s, "end" => end_s})
        end

      %{
        id: op.id,
        operation_type: op_type,
        params: encoded_params,
        position: op.position,
        color: Map.get(@operation_colors, op.operation_type, "#6b7280")
      }
    end)
  end

  defp ms_to_seconds(nil), do: nil
  defp ms_to_seconds(ms) when is_number(ms), do: ms / 1000.0

  defp params_with_seconds(params) do
    start_s = ms_to_seconds(params["start_ms"]) || params["start"] || 0
    end_s = ms_to_seconds(params["end_ms"]) || params["end"] || 5
    Map.merge(params, %{"start" => start_s, "end" => end_s})
  end

  defp region_params(:fade_in, start_s, end_s) do
    start_ms = round(start_s * 1000)
    end_ms = round(end_s * 1000)
    duration_ms = max(end_ms - start_ms, 0)
    %{"start_ms" => start_ms, "end_ms" => end_ms, "duration_ms" => duration_ms}
  end

  defp region_params(:fade_out, start_s, end_s) do
    start_ms = round(start_s * 1000)
    end_ms = round(end_s * 1000)
    duration_ms = max(end_ms - start_ms, 0)
    %{"start_ms" => start_ms, "end_ms" => end_ms, "duration_ms" => duration_ms}
  end

  defp region_params(:gain, start_s, end_s) do
    %{"start_ms" => round(start_s * 1000), "end_ms" => round(end_s * 1000), "level" => 1.0}
  end

  defp region_params(_type, start_s, end_s) do
    %{"start_ms" => round(start_s * 1000), "end_ms" => round(end_s * 1000)}
  end

  defp default_params(:crop), do: %{"start_ms" => 0, "end_ms" => 5000}
  defp default_params(:trim), do: %{"start_ms" => 0, "end_ms" => 2000}
  defp default_params(:fade_in), do: %{"start_ms" => 0, "end_ms" => 3000, "duration_ms" => 3000}
  defp default_params(:fade_out), do: %{"start_ms" => 0, "end_ms" => 3000, "duration_ms" => 3000}
  defp default_params(:split), do: %{"position_ms" => 5000, "position_sec" => 5.0}
  defp default_params(:gain), do: %{"start_ms" => 0, "end_ms" => 10000, "level" => 1.0}
  defp default_params(:pitch_shift), do: %{"semitones" => 0}
  defp default_params(:time_stretch), do: %{"tempo_factor" => 1.0}

  defp operation_label(:crop), do: "Crop"
  defp operation_label(:trim), do: "Trim"
  defp operation_label(:fade_in), do: "Fade In"
  defp operation_label(:fade_out), do: "Fade Out"
  defp operation_label(:split), do: "Split"
  defp operation_label(:gain), do: "Gain"
  defp operation_label(:pitch_shift), do: "Pitch"
  defp operation_label(:time_stretch), do: "Stretch"

  defp operation_icon(:crop), do: "[ ]"
  defp operation_icon(:trim), do: ">|<"
  defp operation_icon(:fade_in), do: "/\\"
  defp operation_icon(:fade_out), do: "\\/"
  defp operation_icon(:split), do: "| |"
  defp operation_icon(:gain), do: "+/-"
  defp operation_icon(:pitch_shift), do: "^v"
  defp operation_icon(:time_stretch), do: "<>"

  defp operation_button_active(:crop), do: "bg-blue-600 text-white"
  defp operation_button_active(:trim), do: "bg-red-600 text-white"
  defp operation_button_active(:fade_in), do: "bg-green-600 text-white"
  defp operation_button_active(:fade_out), do: "bg-green-600 text-white"
  defp operation_button_active(:split), do: "bg-yellow-600 text-black"
  defp operation_button_active(:gain), do: "bg-orange-600 text-white"
  defp operation_button_active(:pitch_shift), do: "bg-cyan-600 text-white"
  defp operation_button_active(:time_stretch), do: "bg-teal-600 text-white"

  defp stem_color(stem_type) do
    case to_string(stem_type) do
      "vocals" -> "text-purple-400"
      "drums" -> "text-blue-400"
      "bass" -> "text-green-400"
      "other" -> "text-amber-400"
      "guitar" -> "text-rose-400"
      "piano" -> "text-cyan-400"
      "electric_guitar" -> "text-red-400"
      "acoustic_guitar" -> "text-orange-400"
      "synth" -> "text-pink-400"
      "strings" -> "text-teal-400"
      "wind" -> "text-sky-400"
      _ -> "text-gray-400"
    end
  end

  defp stem_label(stem_type) do
    stem_type
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp get_track_duration(assigns) do
    track = assigns[:track]
    analysis = assigns[:structure_segments]

    cond do
      # Try to get duration from analysis results
      track && track.analysis_results && track.analysis_results != [] ->
        result = List.first(track.analysis_results)

        cond do
          result.features && is_map(result.features) && is_number(result.features["duration"]) ->
            result.features["duration"]

          true ->
            estimate_duration_from_segments(analysis)
        end

      # Estimate from structure segments
      analysis && analysis != [] ->
        estimate_duration_from_segments(analysis)

      true ->
        180.0
    end
  end

  defp estimate_duration_from_segments(nil), do: 180.0
  defp estimate_duration_from_segments([]), do: 180.0

  defp estimate_duration_from_segments(segments) do
    segments
    |> Enum.map(fn seg ->
      end_ms = seg["end_ms"] || seg["end"] || seg[:end_ms] || seg[:end] || 0
      end_ms / 1000
    end)
    |> Enum.max(fn -> 180.0 end)
  end

  @doc false
  defp time_grid_markers(duration) when is_number(duration) and duration > 0 do
    # Choose interval based on duration
    interval =
      cond do
        duration <= 30 -> 1.0
        duration <= 120 -> 5.0
        duration <= 300 -> 10.0
        duration <= 600 -> 30.0
        true -> 60.0
      end

    major_interval = interval * 4

    count = trunc(duration / interval)

    Enum.map(0..count, fn i ->
      time = i * interval
      percent = Float.round(time / duration * 100, 2)
      major = rem(trunc(time), trunc(major_interval)) == 0

      label =
        if major or interval <= 5.0 do
          mins = div(trunc(time), 60)
          secs = rem(trunc(time), 60)
          "#{mins}:#{String.pad_leading(to_string(secs), 2, "0")}"
        else
          ""
        end

      %{percent: percent, label: label, major: major}
    end)
    |> Enum.filter(fn m -> m.percent <= 100 end)
  end

  defp time_grid_markers(_), do: []

end
