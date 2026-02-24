defmodule SoundForgeWeb.DawLive do
  @moduledoc """
  DAW (Digital Audio Workstation) LiveView for non-destructive stem editing.

  Displays per-stem WaveSurfer waveforms with the Regions plugin, allowing
  users to create, resize, and remove edit operations (crop, trim, fade in,
  fade out, split, gain) via draggable colored regions.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Music
  alias SoundForge.DAW

  @operation_colors %{
    crop: "#3b82f6",
    trim: "#ef4444",
    fade_in: "#22c55e",
    fade_out: "#22c55e",
    split: "#eab308",
    gain: "#f97316"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "DAW Editor")
     |> assign(:track, nil)
     |> assign(:stems, [])
     |> assign(:stem_operations, %{})
     |> assign(:selected_operation, :crop)
     |> assign(:selected_stem_id, nil)
     |> assign(:previewing, false)
     |> assign(:export_status, nil)}
  end

  @impl true
  def handle_params(%{"track_id" => track_id}, _uri, socket) do
    user_id = socket.assigns[:current_scope] && socket.assigns.current_scope.user.id

    try do
      track =
        Music.get_track!(track_id)
        |> SoundForge.Repo.preload(:stems)

      stems = track.stems

      # Load edit operations per stem
      stem_operations =
        Map.new(stems, fn stem ->
          ops = DAW.list_edit_operations(stem.id, user_id)
          {stem.id, ops}
        end)

      {:noreply,
       socket
       |> assign(:page_title, "DAW - #{track.title}")
       |> assign(:track, track)
       |> assign(:stems, stems)
       |> assign(:stem_operations, stem_operations)}
    rescue
      Ecto.NoResultsError ->
        {:noreply,
         socket
         |> put_flash(:error, "Track not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  # -- Region Events from JS Hook --

  @impl true
  def handle_event("region_created", params, socket) do
    %{
      "stem_id" => stem_id,
      "start" => start_time,
      "end" => end_time
    } = params

    user_id = current_user_id(socket)
    operation_type = socket.assigns.selected_operation

    # Determine next position for this stem
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

      # Merge new region bounds with existing params to preserve type-specific
      # keys (duration_ms for fades, level for gain)
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

  # -- Toolbar Events --

  @valid_operations ~w(crop trim fade_in fade_out split gain)a

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
  def handle_event("apply_operation", %{"stem_id" => stem_id}, socket) do
    user_id = current_user_id(socket)
    operation_type = socket.assigns.selected_operation

    # For split operations, ask the JS hook for the current cursor position first
    if operation_type == :split do
      {:noreply,
       push_event(socket, "request_cursor_for_split", %{stem_id: stem_id})}
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

  # -- Split Events --

  @impl true
  def handle_event(
        "apply_split",
        %{"stem_id" => stem_id, "cursor_position" => cursor_position},
        socket
      ) do
    user_id = current_user_id(socket)
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

  # -- Preview Playback --

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

  # -- Export Events --

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
            # Reload stems to include the newly created edited stem
            track = Music.get_track!(socket.assigns.track.id) |> SoundForge.Repo.preload(:stems)
            assign(socket, :stems, track.stems)
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

  # -- Template --

  @impl true
  def render(assigns) do
    ~H"""
    <div id="daw-preview-container" phx-hook="DawPreview" class="min-h-screen bg-gray-900 text-white">
      <!-- Header -->
      <div class="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/"}
            class="text-gray-400 hover:text-white transition-colors"
            aria-label="Back to library"
          >
            <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
            </svg>
          </.link>

          <!-- Preview Play/Pause Button -->
          <button
            phx-click="toggle_preview"
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
            <h1 class="text-xl font-bold text-white">
              DAW Editor
            </h1>
            <p :if={@track} class="text-sm text-gray-400">
              {@track.title}
              <span :if={@track.artist} class="text-gray-500">
                - {@track.artist}
              </span>
            </p>
          </div>

          <!-- Global Operation Selector -->
          <div class="ml-auto flex items-center gap-2">
            <span class="text-xs text-gray-500 mr-2">Tool:</span>
            <button
              :for={op <- [:crop, :trim, :fade_in, :fade_out, :split, :gain]}
              phx-click="select_operation"
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

      <!-- Stem Tracks -->
      <div class="p-6 space-y-4">
        <div
          :if={@stems == []}
          class="text-center py-20 text-gray-500"
        >
          <p class="text-lg">No stems available for this track.</p>
          <p class="text-sm mt-2">Process the track first to separate stems.</p>
        </div>

        <div
          :for={stem <- @stems}
          class={"bg-gray-800 rounded-lg border transition-colors " <>
            if(@selected_stem_id == stem.id,
              do: "border-purple-500",
              else: "border-gray-700 hover:border-gray-600")}
          phx-click="select_stem"
          phx-value-stem-id={stem.id}
        >
          <!-- Stem Header -->
          <div class="flex items-center gap-3 px-4 py-3 border-b border-gray-700/50">
            <!-- Stem Type Label -->
            <span class={"text-sm font-semibold w-24 " <> stem_color(stem.stem_type)}>
              {stem_label(stem.stem_type)}
            </span>

            <!-- Operation Count Badge -->
            <span class="text-xs bg-gray-700 text-gray-300 px-2 py-0.5 rounded-full">
              {length(Map.get(@stem_operations, stem.id, []))} ops
            </span>

            <!-- Stem Toolbar -->
            <div class="ml-auto flex items-center gap-1">
              <button
                :for={op <- [:crop, :trim, :fade_in, :fade_out, :split, :gain]}
                phx-click="apply_operation"
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

              <!-- Undo Button -->
              <button
                phx-click="undo_last"
                phx-value-stem_id={stem.id}
                title="Undo last operation"
                class="px-2 py-1 rounded text-xs bg-gray-700/50 text-gray-400 hover:bg-gray-700 hover:text-white transition-colors"
              >
                Undo
              </button>
            </div>
          </div>

          <!-- Waveform Container -->
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
            class="px-4 py-3"
          >
            <div class="h-24 rounded bg-gray-900/50 flex items-center justify-center">
              <span class="text-sm text-gray-600">Loading waveform...</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Private Helpers --

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

  defp current_user_id(socket) do
    case socket.assigns[:current_scope] do
      %{user: %{id: id}} -> id
      _ -> nil
    end
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
          # Split operations use position_sec instead of start/end regions
          pos_sec =
            op.params["position_sec"] ||
              ms_to_seconds(op.params["position_ms"]) ||
              op.params["start"] ||
              5.0

          Map.merge(op.params, %{"position_sec" => pos_sec})
        else
          # Convert start_ms/end_ms back to seconds for WaveSurfer regions,
          # falling back to legacy start/end keys for older operations.
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

  # Builds operation-type-aware params from a region's start/end times (seconds).
  # Fades get duration_ms computed from the region length (or default 2000ms).
  # Gain includes the level key (defaults to 1.0).
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

  defp operation_label(:crop), do: "Crop"
  defp operation_label(:trim), do: "Trim"
  defp operation_label(:fade_in), do: "Fade In"
  defp operation_label(:fade_out), do: "Fade Out"
  defp operation_label(:split), do: "Split"
  defp operation_label(:gain), do: "Gain"

  defp operation_icon(:crop), do: "[ ]"
  defp operation_icon(:trim), do: ">|<"
  defp operation_icon(:fade_in), do: "/\\"
  defp operation_icon(:fade_out), do: "\\/"
  defp operation_icon(:split), do: "| |"
  defp operation_icon(:gain), do: "+/-"

  defp operation_button_active(:crop), do: "bg-blue-600 text-white"
  defp operation_button_active(:trim), do: "bg-red-600 text-white"
  defp operation_button_active(:fade_in), do: "bg-green-600 text-white"
  defp operation_button_active(:fade_out), do: "bg-green-600 text-white"
  defp operation_button_active(:split), do: "bg-yellow-600 text-black"
  defp operation_button_active(:gain), do: "bg-orange-600 text-white"

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
end
