defmodule SoundForgeWeb.Live.Components.ChromaticPadsComponent do
  @moduledoc """
  Chromatic Pads component rendered inline within the dashboard as tab=pads.

  Provides a 4x4 MPC-style pad grid with bank management, per-pad stem
  assignment, waveform start/end selection, pitch/volume/velocity controls,
  drag-and-drop from the track browser, Quick Load from DJ deck stems,
  and master volume/BPM display.

  PubSub messages are forwarded from the parent DashboardLive via
  `send_update/3`.
  """
  use SoundForgeWeb, :live_component

  alias SoundForge.Sampler

  @pad_key_labels ~w(1 2 3 4 Q W E R A S D F Z X C V)

  # -- Lifecycle --

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:banks, [])
     |> assign(:current_bank, nil)
     |> assign(:selected_pad, nil)
     |> assign(:master_volume, 1.0)
     |> assign(:available_stems, [])
     |> assign(:creating_bank, false)
     |> assign(:renaming_bank, false)
     |> assign(:new_bank_name, "")
     |> assign(:rename_bank_name, "")
     |> assign(:initialized, false)
     |> assign(:pad_key_labels, @pad_key_labels)
     # MIDI Learn state
     |> assign(:midi_learn_mode, false)
     |> assign(:midi_learn_target, nil)
     |> assign(:midi_available, false)
     |> assign(:midi_devices, [])
     |> assign(:midi_activity, false)
     |> assign(:midi_mappings_count, 0)
     # Preset import state
     |> assign(:importing_preset, false)
     |> assign(:import_error, nil)
     |> assign(:import_success, nil)
     |> allow_upload(:preset_file,
       accept: ~w(.touchosc .xpm .pgm),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def update(%{auto_cues_complete: _payload}, socket) do
    # Auto-cues completed for a track -- refresh available stems in case
    # new stems are now available from the same processing pipeline.
    scope = socket.assigns[:current_scope]
    stems = if scope, do: list_user_stems(scope), else: []
    {:ok, assign(socket, :available_stems, stems)}
  end

  def update(assigns, socket) do
    socket = assign(socket, :current_scope, assigns[:current_scope])
    socket = assign(socket, :current_user_id, assigns[:current_user_id])
    socket = assign(socket, :id, assigns[:id])

    if not socket.assigns.initialized do
      user_id = assigns[:current_user_id]
      banks = Sampler.list_banks(user_id)

      {banks, current_bank} =
        case banks do
          [] ->
            {:ok, bank} = Sampler.create_bank(%{name: "Bank A", user_id: user_id, position: 0})
            {[bank], bank}

          [first | _] = all ->
            {all, first}
        end

      stems = list_user_stems(assigns[:current_scope])

      midi_count =
        if current_bank do
          Sampler.bank_midi_mappings(user_id, current_bank.id) |> length()
        else
          0
        end

      {:ok,
       socket
       |> assign(:banks, banks)
       |> assign(:current_bank, current_bank)
       |> assign(:available_stems, stems)
       |> assign(:midi_mappings_count, midi_count)
       |> assign(:initialized, true)}
    else
      # Handle auto-load request from "Load in Pads" button in track detail
      socket =
        case assigns[:auto_load_track_id] do
          nil ->
            socket

          track_id ->
            track =
              SoundForge.Music.get_track!(track_id)
              |> SoundForge.Repo.preload(:stems)

            if track.stems != [] && socket.assigns[:current_bank] do
              case Sampler.quick_load_stems(socket.assigns.current_bank, track.stems) do
                {:ok, updated_bank} -> assign(socket, :current_bank, updated_bank)
                _ -> socket
              end
            else
              socket
            end
        end

      {:ok, socket}
    end
  end

  # -- Render --

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="chromatic-pads"
      phx-hook="ChromaticPads"
      phx-target={@myself}
      class="flex flex-col h-full bg-gray-950"
    >
      <%!-- Top Bar: Bank selector + Master controls + MIDI --%>
      <div class="flex items-center justify-between px-6 py-3 bg-gray-900 border-b border-gray-800">
        <div class="flex items-center gap-3">
          <h2 class="text-lg font-semibold text-white">Pads</h2>

          <%!-- Bank Selector --%>
          <div class="flex items-center gap-2">
            <select
              phx-change="switch_bank"
              phx-target={@myself}
              class="select select-sm bg-gray-800 border-gray-700 text-white text-sm"
            >
              <option
                :for={bank <- @banks}
                value={bank.id}
                selected={@current_bank && bank.id == @current_bank.id}
              >
                {bank.name}
              </option>
            </select>

            <button
              phx-click="start_create_bank"
              phx-target={@myself}
              class="btn btn-ghost btn-xs text-purple-400 hover:text-purple-300"
              title="New bank"
            >
              <span class="hero-plus w-4 h-4"></span>
            </button>

            <button
              :if={@current_bank}
              phx-click="start_rename_bank"
              phx-target={@myself}
              class="btn btn-ghost btn-xs text-gray-400 hover:text-white"
              title="Rename bank"
            >
              <span class="hero-pencil w-4 h-4"></span>
            </button>

            <button
              :if={@current_bank && length(@banks) > 1}
              phx-click="delete_bank"
              phx-target={@myself}
              data-confirm="Delete this bank and all its pad assignments?"
              class="btn btn-ghost btn-xs text-red-400 hover:text-red-300"
              title="Delete bank"
            >
              <span class="hero-trash w-4 h-4"></span>
            </button>
          </div>

          <%!-- Divider --%>
          <div class="w-px h-5 bg-gray-700" />

          <%!-- MIDI Learn Toggle + Activity Indicator --%>
          <div class="flex items-center gap-2">
            <%!-- MIDI Activity LED --%>
            <div
              class={[
                "w-2.5 h-2.5 rounded-full transition-colors",
                if(@midi_activity, do: "bg-green-400", else: "bg-gray-600")
              ]}
              title={if(@midi_available, do: "MIDI connected", else: "No MIDI")}
            />

            <%!-- MIDI Learn button --%>
            <button
              phx-click="toggle_midi_learn"
              phx-target={@myself}
              class={[
                "btn btn-xs",
                if(@midi_learn_mode,
                  do: "btn-warning animate-pulse",
                  else: "btn-ghost text-gray-400 hover:text-white"
                )
              ]}
              title={if(@midi_learn_mode, do: "Cancel MIDI Learn", else: "Enter MIDI Learn mode")}
            >
              <span class="hero-signal w-4 h-4"></span>
              <%= if @midi_learn_mode do %>
                Learning...
              <% else %>
                MIDI Learn
              <% end %>
            </button>

            <%!-- MIDI mappings badge --%>
            <span
              :if={@midi_mappings_count > 0}
              class="badge badge-xs badge-accent"
              title={"#{@midi_mappings_count} MIDI mapping(s)"}
            >
              {@midi_mappings_count}
            </span>

            <%!-- Import Preset button --%>
            <button
              phx-click="start_import_preset"
              phx-target={@myself}
              class="btn btn-ghost btn-xs text-gray-400 hover:text-white"
              title="Import preset (.touchosc, .xpm, .pgm)"
            >
              <span class="hero-arrow-up-tray w-4 h-4"></span>
              Import
            </button>
          </div>
        </div>

        <%!-- Master Volume + BPM --%>
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2">
            <label class="text-xs text-gray-500">Master</label>
            <input
              type="range"
              min="0"
              max="100"
              value={round(@master_volume * 100)}
              phx-change="set_master_volume"
              phx-target={@myself}
              class="range range-xs range-primary w-24"
            />
            <span class="text-xs text-gray-400 tabular-nums w-8 text-right">
              {round(@master_volume * 100)}%
            </span>
          </div>
          <div :if={@current_bank && @current_bank.bpm} class="flex items-center gap-1">
            <span class="text-xs text-gray-500">BPM</span>
            <span class="text-sm font-mono text-purple-300">
              {Float.round(@current_bank.bpm * 1.0, 1)}
            </span>
          </div>
        </div>
      </div>

      <%!-- MIDI Learn Mode Banner --%>
      <div
        :if={@midi_learn_mode}
        class="px-6 py-2 bg-yellow-900/30 border-b border-yellow-700/50"
      >
        <p class="text-xs text-yellow-300">
          MIDI Learn active -- click a pad or parameter, then move a control on your MIDI device.
          <%= if @midi_learn_target do %>
            <span class="font-medium">
              Waiting for MIDI input for:
              {format_learn_target(@midi_learn_target)}
            </span>
          <% end %>
        </p>
      </div>

      <%!-- Create Bank Modal --%>
      <div
        :if={@creating_bank}
        class="absolute inset-0 z-50 flex items-center justify-center bg-black/60"
      >
        <form
          phx-submit="create_bank"
          phx-target={@myself}
          class="bg-gray-800 border border-gray-700 rounded-lg p-6 w-80 shadow-xl"
        >
          <h3 class="text-sm font-semibold text-white mb-3">New Bank</h3>
          <input
            type="text"
            name="name"
            value={@new_bank_name}
            phx-change="update_new_bank_name"
            phx-target={@myself}
            placeholder="Bank name..."
            class="input input-sm w-full bg-gray-900 border-gray-700 text-white mb-3"
            autofocus
          />
          <div class="flex justify-end gap-2">
            <button
              type="button"
              phx-click="cancel_create_bank"
              phx-target={@myself}
              class="btn btn-ghost btn-sm"
            >
              Cancel
            </button>
            <button type="submit" class="btn btn-primary btn-sm">Create</button>
          </div>
        </form>
      </div>

      <%!-- Rename Bank Modal --%>
      <div
        :if={@renaming_bank}
        class="absolute inset-0 z-50 flex items-center justify-center bg-black/60"
      >
        <form
          phx-submit="rename_bank"
          phx-target={@myself}
          class="bg-gray-800 border border-gray-700 rounded-lg p-6 w-80 shadow-xl"
        >
          <h3 class="text-sm font-semibold text-white mb-3">Rename Bank</h3>
          <input
            type="text"
            name="name"
            value={@rename_bank_name}
            phx-change="update_rename_bank_name"
            phx-target={@myself}
            placeholder="Bank name..."
            class="input input-sm w-full bg-gray-900 border-gray-700 text-white mb-3"
            autofocus
          />
          <div class="flex justify-end gap-2">
            <button
              type="button"
              phx-click="cancel_rename_bank"
              phx-target={@myself}
              class="btn btn-ghost btn-sm"
            >
              Cancel
            </button>
            <button type="submit" class="btn btn-primary btn-sm">Rename</button>
          </div>
        </form>
      </div>

      <%!-- Import Preset Modal --%>
      <div
        :if={@importing_preset}
        class="absolute inset-0 z-50 flex items-center justify-center bg-black/60"
      >
        <div class="bg-gray-800 border border-gray-700 rounded-lg p-6 w-96 shadow-xl">
          <h3 class="text-sm font-semibold text-white mb-3">Import Preset</h3>
          <p class="text-xs text-gray-400 mb-4">
            Upload a .touchosc, .xpm (MPC X/Live/One), or .pgm (MPC1000/2500) file
            to create a new bank with pre-configured pad assignments and MIDI mappings.
          </p>

          <form
            id="preset-upload-form"
            phx-submit="upload_preset"
            phx-target={@myself}
            phx-change="validate_preset"
          >
            <.live_file_input upload={@uploads.preset_file} class="file-input file-input-sm w-full bg-gray-900 border-gray-700 text-white mb-3" />

            <div :if={@import_error} class="text-xs text-red-400 mb-2">{@import_error}</div>
            <div :if={@import_success} class="text-xs text-green-400 mb-2">{@import_success}</div>

            <%= for entry <- @uploads.preset_file.entries do %>
              <div class="flex items-center gap-2 mb-2">
                <span class="text-xs text-gray-300 flex-1 truncate">{entry.client_name}</span>
                <span class="text-xs text-gray-500">{format_bytes(entry.client_size)}</span>
                <button
                  type="button"
                  phx-click="cancel_preset_entry"
                  phx-target={@myself}
                  phx-value-ref={entry.ref}
                  class="text-xs text-red-400"
                >
                  Remove
                </button>
              </div>
              <progress :if={entry.progress > 0} class="progress progress-primary w-full h-1 mb-2" value={entry.progress} max="100" />
            <% end %>

            <div class="flex justify-end gap-2 mt-3">
              <button
                type="button"
                phx-click="cancel_import_preset"
                phx-target={@myself}
                class="btn btn-ghost btn-sm"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="btn btn-primary btn-sm"
                disabled={@uploads.preset_file.entries == []}
              >
                Import
              </button>
            </div>
          </form>
        </div>
      </div>

      <%!-- Main Content: Pad Grid + Detail Panel --%>
      <div class="flex flex-1 overflow-hidden relative">
        <%!-- Left: 4x4 Pad Grid --%>
        <div class="flex-1 flex flex-col items-center justify-center p-6">
          <div class="grid grid-cols-4 gap-3 max-w-lg w-full">
            <%= for {pad, idx} <- Enum.with_index(bank_pads(@current_bank)) do %>
              <div
                data-pad-id={pad.id}
                data-pad-index={idx}
                data-pad-drop={pad.id}
                data-pad-volume={pad.volume}
                data-pad-pitch={pad.pitch}
                data-pad-velocity={pad.velocity}
                data-pad-start-time={pad.start_time}
                data-pad-end-time={pad.end_time}
                phx-click={if @midi_learn_mode, do: "midi_learn_pad", else: "select_pad"}
                phx-target={@myself}
                phx-value-pad-id={pad.id}
                phx-value-pad-index={idx}
                class={[
                  "aspect-square rounded-lg flex flex-col items-center justify-center cursor-pointer transition-all",
                  "border-2 text-xs font-bold select-none relative",
                  pad_border_class(pad, @selected_pad, @midi_learn_mode),
                  if(pad.stem_id, do: "hover:brightness-110", else: "hover:bg-gray-700")
                ]}
                style={pad_bg_style(pad)}
              >
                <%!-- MIDI Learn overlay when in learn mode --%>
                <div
                  :if={@midi_learn_mode}
                  class="absolute inset-0 rounded-lg bg-yellow-500/10 border-2 border-yellow-400/30 flex items-center justify-center"
                >
                  <span class="text-[10px] text-yellow-300">Map</span>
                </div>

                <span class="text-[10px] text-white/50 mb-0.5">
                  {Enum.at(@pad_key_labels, idx)}
                </span>
                <span class="text-white/90 text-sm truncate max-w-[90%]">
                  {pad.label || "Pad #{idx + 1}"}
                </span>
                <span
                  :if={pad.stem && pad.stem.stem_type}
                  class="text-[10px] text-white/60 mt-0.5 truncate max-w-[90%]"
                >
                  {pad.stem.stem_type |> to_string() |> String.capitalize()}
                </span>
              </div>
            <% end %>
          </div>

          <%!-- Quick Load + MIDI Device Info --%>
          <div class="mt-4 flex items-center gap-3">
            <button
              phx-click="quick_load"
              phx-target={@myself}
              class="btn btn-sm btn-outline btn-primary"
            >
              <span class="hero-bolt w-4 h-4"></span>
              Quick Load Stems
            </button>

            <span :if={@midi_devices != []} class="text-[10px] text-gray-500">
              MIDI: {Enum.map_join(@midi_devices, ", ", & &1["name"])}
            </span>
          </div>
        </div>

        <%!-- Right: Pad Detail Panel --%>
        <aside
          :if={@selected_pad}
          class="w-80 bg-gray-900 border-l border-gray-800 overflow-y-auto p-4 space-y-4"
        >
          <div class="flex items-center justify-between">
            <h3 class="text-sm font-semibold text-white">
              Pad {pad_display_index(@selected_pad, @current_bank)} Settings
            </h3>
            <button
              phx-click="deselect_pad"
              phx-target={@myself}
              class="btn btn-ghost btn-xs text-gray-400"
            >
              <span class="hero-x-mark w-4 h-4"></span>
            </button>
          </div>

          <%!-- Stem Assignment --%>
          <div>
            <label class="text-xs text-gray-500 block mb-1">Assigned Stem</label>
            <%= if @selected_pad.stem do %>
              <div class="flex items-center gap-2 px-3 py-2 bg-gray-800 rounded-lg">
                <div
                  class="w-3 h-3 rounded-full"
                  style={"background-color: #{Sampler.stem_type_color(@selected_pad.stem.stem_type)}"}
                />
                <span class="text-sm text-gray-300 flex-1">
                  {@selected_pad.stem.stem_type |> to_string() |> String.capitalize()}
                </span>
                <button
                  phx-click="clear_pad_stem"
                  phx-target={@myself}
                  class="text-xs text-red-400 hover:text-red-300"
                >
                  Clear
                </button>
              </div>
            <% else %>
              <p class="text-xs text-gray-600">No stem assigned. Drag a stem or select below:</p>
            <% end %>

            <%!-- Stem Picker --%>
            <div class="mt-2 max-h-32 overflow-y-auto space-y-1">
              <div
                :for={stem <- @available_stems}
                data-stem-drag={stem.id}
                phx-click="assign_stem"
                phx-target={@myself}
                phx-value-pad-id={@selected_pad.id}
                phx-value-stem-id={stem.id}
                class="flex items-center gap-2 px-2 py-1.5 bg-gray-800/50 rounded cursor-pointer hover:bg-gray-700 transition-colors"
              >
                <div
                  class="w-2.5 h-2.5 rounded-full"
                  style={"background-color: #{Sampler.stem_type_color(stem.stem_type)}"}
                />
                <span class="text-xs text-gray-300">
                  {stem.stem_type |> to_string() |> String.capitalize()}
                </span>
                <span class="text-[10px] text-gray-600 ml-auto truncate max-w-[120px]">
                  {stem_track_label(stem)}
                </span>
              </div>
              <p :if={@available_stems == []} class="text-xs text-gray-600">
                No stems available. Process a track first.
              </p>
            </div>
          </div>

          <%!-- Label --%>
          <div>
            <label class="text-xs text-gray-500 block mb-1">Label</label>
            <input
              type="text"
              name="label"
              value={@selected_pad.label || ""}
              phx-blur="update_pad_label"
              phx-target={@myself}
              phx-value-pad-id={@selected_pad.id}
              class="input input-xs w-full bg-gray-800 border-gray-700 text-white"
              placeholder="Pad label..."
            />
          </div>

          <%!-- Volume (with MIDI Learn button) --%>
          <div>
            <div class="flex items-center justify-between mb-1">
              <label class="text-xs text-gray-500">
                Volume: {round(@selected_pad.volume * 100)}%
              </label>
              <button
                :if={@midi_learn_mode}
                phx-click="midi_learn_param"
                phx-target={@myself}
                phx-value-param="pad_volume"
                phx-value-pad-index={pad_display_index(@selected_pad, @current_bank) - 1}
                class="text-[10px] text-yellow-400 hover:text-yellow-300"
              >
                [Map]
              </button>
            </div>
            <input
              type="range"
              min="0"
              max="100"
              value={round(@selected_pad.volume * 100)}
              phx-change="update_pad_volume"
              phx-target={@myself}
              phx-value-pad-id={@selected_pad.id}
              class="range range-xs range-primary w-full"
            />
          </div>

          <%!-- Pitch (with MIDI Learn button) --%>
          <div>
            <div class="flex items-center justify-between mb-1">
              <label class="text-xs text-gray-500">
                Pitch: {format_pitch(@selected_pad.pitch)} st
              </label>
              <button
                :if={@midi_learn_mode}
                phx-click="midi_learn_param"
                phx-target={@myself}
                phx-value-param="pad_pitch"
                phx-value-pad-index={pad_display_index(@selected_pad, @current_bank) - 1}
                class="text-[10px] text-yellow-400 hover:text-yellow-300"
              >
                [Map]
              </button>
            </div>
            <input
              type="range"
              min="-24"
              max="24"
              step="1"
              value={round(@selected_pad.pitch)}
              phx-change="update_pad_pitch"
              phx-target={@myself}
              phx-value-pad-id={@selected_pad.id}
              class="range range-xs range-secondary w-full"
            />
          </div>

          <%!-- Velocity (with MIDI Learn button) --%>
          <div>
            <div class="flex items-center justify-between mb-1">
              <label class="text-xs text-gray-500">
                Velocity: {round(@selected_pad.velocity * 100)}%
              </label>
              <button
                :if={@midi_learn_mode}
                phx-click="midi_learn_param"
                phx-target={@myself}
                phx-value-param="pad_velocity"
                phx-value-pad-index={pad_display_index(@selected_pad, @current_bank) - 1}
                class="text-[10px] text-yellow-400 hover:text-yellow-300"
              >
                [Map]
              </button>
            </div>
            <input
              type="range"
              min="0"
              max="100"
              value={round(@selected_pad.velocity * 100)}
              phx-change="update_pad_velocity"
              phx-target={@myself}
              phx-value-pad-id={@selected_pad.id}
              class="range range-xs range-accent w-full"
            />
          </div>

          <%!-- Waveform Start / End --%>
          <div>
            <label class="text-xs text-gray-500 block mb-1">Waveform Region (seconds)</label>
            <div class="flex items-center gap-2">
              <div class="flex-1">
                <label class="text-[10px] text-gray-600">Start</label>
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={Float.round(@selected_pad.start_time * 1.0, 2)}
                  phx-blur="update_pad_start_time"
                  phx-target={@myself}
                  phx-value-pad-id={@selected_pad.id}
                  class="input input-xs w-full bg-gray-800 border-gray-700 text-white tabular-nums"
                />
              </div>
              <div class="flex-1">
                <label class="text-[10px] text-gray-600">End</label>
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={@selected_pad.end_time && Float.round(@selected_pad.end_time * 1.0, 2)}
                  phx-blur="update_pad_end_time"
                  phx-target={@myself}
                  phx-value-pad-id={@selected_pad.id}
                  placeholder="--"
                  class="input input-xs w-full bg-gray-800 border-gray-700 text-white tabular-nums"
                />
              </div>
            </div>
          </div>

          <%!-- Color Picker --%>
          <div>
            <label class="text-xs text-gray-500 block mb-1">Pad Color</label>
            <div class="flex gap-1.5 flex-wrap">
              <button
                :for={color <- pad_color_options()}
                phx-click="update_pad_color"
                phx-target={@myself}
                phx-value-pad-id={@selected_pad.id}
                phx-value-color={color}
                class={[
                  "w-6 h-6 rounded-md border-2 transition-all",
                  if(@selected_pad.color == color,
                    do: "border-white scale-110",
                    else: "border-transparent hover:border-gray-500"
                  )
                ]}
                style={"background-color: #{color}"}
              />
            </div>
          </div>

          <%!-- Clear Pad --%>
          <button
            :if={@selected_pad.stem_id}
            phx-click="clear_pad_full"
            phx-target={@myself}
            phx-value-pad-id={@selected_pad.id}
            class="btn btn-ghost btn-sm text-red-400 hover:text-red-300 w-full"
          >
            Clear Pad Assignment
          </button>
        </aside>
      </div>
    </div>
    """
  end

  # -- Event Handlers --

  # Bank management

  @impl true
  def handle_event("switch_bank", %{"_target" => _, "value" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("switch_bank", params, socket) do
    bank_id = params["value"] || params["bank_id"]

    if bank_id && bank_id != "" do
      bank = Sampler.get_bank!(bank_id)
      user_id = socket.assigns.current_user_id
      mappings = Sampler.bank_midi_mappings(user_id, bank.id)

      {:noreply,
       socket
       |> assign(:current_bank, bank)
       |> assign(:selected_pad, nil)
       |> assign(:midi_mappings_count, length(mappings))
       |> push_event("load_midi_mappings", %{mappings: mappings})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("start_create_bank", _params, socket) do
    {:noreply, assign(socket, creating_bank: true, new_bank_name: "")}
  end

  def handle_event("cancel_create_bank", _params, socket) do
    {:noreply, assign(socket, creating_bank: false)}
  end

  def handle_event("update_new_bank_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :new_bank_name, name)}
  end

  def handle_event("create_bank", %{"name" => name}, socket) do
    user_id = socket.assigns.current_user_id
    position = length(socket.assigns.banks)
    bank_name = if name == "", do: "Bank #{position + 1}", else: name

    case Sampler.create_bank(%{name: bank_name, user_id: user_id, position: position}) do
      {:ok, bank} ->
        banks = Sampler.list_banks(user_id)

        {:noreply,
         socket
         |> assign(:banks, banks)
         |> assign(:current_bank, bank)
         |> assign(:creating_bank, false)
         |> assign(:selected_pad, nil)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("start_rename_bank", _params, socket) do
    name = socket.assigns.current_bank && socket.assigns.current_bank.name || ""
    {:noreply, assign(socket, renaming_bank: true, rename_bank_name: name)}
  end

  def handle_event("cancel_rename_bank", _params, socket) do
    {:noreply, assign(socket, renaming_bank: false)}
  end

  def handle_event("update_rename_bank_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :rename_bank_name, name)}
  end

  def handle_event("rename_bank", %{"name" => name}, socket) do
    bank = socket.assigns.current_bank

    if bank do
      case Sampler.update_bank(bank, %{name: name}) do
        {:ok, updated} ->
          banks = Sampler.list_banks(socket.assigns.current_user_id)

          {:noreply,
           socket
           |> assign(:banks, banks)
           |> assign(:current_bank, %{updated | pads: bank.pads})
           |> assign(:renaming_bank, false)}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_bank", _params, socket) do
    bank = socket.assigns.current_bank
    user_id = socket.assigns.current_user_id

    if bank do
      case Sampler.delete_bank(bank) do
        {:ok, _} ->
          banks = Sampler.list_banks(user_id)

          {banks, current} =
            case banks do
              [] ->
                {:ok, new_bank} = Sampler.create_bank(%{name: "Bank A", user_id: user_id, position: 0})
                {[new_bank], new_bank}

              [first | _] = all ->
                {all, first}
            end

          {:noreply,
           socket
           |> assign(:banks, banks)
           |> assign(:current_bank, current)
           |> assign(:selected_pad, nil)}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Pad selection

  def handle_event("select_pad", %{"pad-id" => pad_id}, socket) do
    pad = Sampler.get_pad!(pad_id)
    {:noreply, assign(socket, :selected_pad, pad)}
  end

  def handle_event("deselect_pad", _params, socket) do
    {:noreply, assign(socket, :selected_pad, nil)}
  end

  # Stem assignment (from click or drag-and-drop)

  def handle_event("assign_stem", %{"pad_id" => pad_id, "stem_id" => stem_id}, socket) do
    pad = Sampler.get_pad!(pad_id)

    case Sampler.assign_stem_to_pad(pad, stem_id) do
      {:ok, updated_pad} ->
        stem = updated_pad.stem
        label = if stem, do: stem.stem_type |> to_string() |> String.capitalize(), else: nil
        color = if stem, do: Sampler.stem_type_color(stem.stem_type), else: "#6b7280"

        {:ok, updated_pad} = Sampler.update_pad(updated_pad, %{label: label, color: color})

        {:noreply, reload_bank(socket, updated_pad)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("assign_stem", %{"pad-id" => pad_id, "stem-id" => stem_id}, socket) do
    handle_event("assign_stem", %{"pad_id" => pad_id, "stem_id" => stem_id}, socket)
  end

  def handle_event("clear_pad_stem", _params, socket) do
    pad = socket.assigns.selected_pad

    if pad do
      case Sampler.assign_stem_to_pad(pad, nil) do
        {:ok, updated_pad} ->
          {:noreply, reload_bank(socket, updated_pad)}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_pad_full", %{"pad-id" => pad_id}, socket) do
    pad = Sampler.get_pad!(pad_id)

    case Sampler.clear_pad(pad) do
      {:ok, updated_pad} ->
        {:noreply, reload_bank(socket, updated_pad)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Pad settings updates

  def handle_event("update_pad_label", %{"pad-id" => pad_id, "value" => label}, socket) do
    pad = Sampler.get_pad!(pad_id)

    case Sampler.update_pad(pad, %{label: label}) do
      {:ok, updated_pad} -> {:noreply, reload_bank(socket, updated_pad)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("update_pad_volume", %{"pad-id" => pad_id, "value" => val}, socket) do
    pad = Sampler.get_pad!(pad_id)
    volume = String.to_integer(val) / 100

    case Sampler.update_pad(pad, %{volume: volume}) do
      {:ok, updated_pad} -> {:noreply, reload_bank(socket, updated_pad)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("update_pad_pitch", %{"pad-id" => pad_id, "value" => val}, socket) do
    pad = Sampler.get_pad!(pad_id)
    pitch = String.to_float("#{val}.0") |> Float.round(0)

    case Sampler.update_pad(pad, %{pitch: pitch}) do
      {:ok, updated_pad} -> {:noreply, reload_bank(socket, updated_pad)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("update_pad_velocity", %{"pad-id" => pad_id, "value" => val}, socket) do
    pad = Sampler.get_pad!(pad_id)
    velocity = String.to_integer(val) / 100

    case Sampler.update_pad(pad, %{velocity: velocity}) do
      {:ok, updated_pad} -> {:noreply, reload_bank(socket, updated_pad)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("update_pad_start_time", %{"pad-id" => pad_id, "value" => val}, socket) do
    pad = Sampler.get_pad!(pad_id)
    start_time = parse_float(val, 0.0)

    case Sampler.update_pad(pad, %{start_time: start_time}) do
      {:ok, updated_pad} -> {:noreply, reload_bank(socket, updated_pad)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("update_pad_end_time", %{"pad-id" => pad_id, "value" => val}, socket) do
    pad = Sampler.get_pad!(pad_id)
    end_time = if val == "" or val == nil, do: nil, else: parse_float(val, nil)

    case Sampler.update_pad(pad, %{end_time: end_time}) do
      {:ok, updated_pad} -> {:noreply, reload_bank(socket, updated_pad)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("update_pad_color", %{"pad-id" => pad_id, "color" => color}, socket) do
    pad = Sampler.get_pad!(pad_id)

    case Sampler.update_pad(pad, %{color: color}) do
      {:ok, updated_pad} -> {:noreply, reload_bank(socket, updated_pad)}
      {:error, _} -> {:noreply, socket}
    end
  end

  # Master volume

  def handle_event("set_master_volume", %{"value" => val}, socket) do
    volume = String.to_integer(val) / 100
    {:noreply, assign(socket, :master_volume, volume)}
  end

  # Quick Load

  def handle_event("quick_load", _params, socket) do
    bank = socket.assigns.current_bank
    scope = socket.assigns.current_scope

    if bank && scope do
      stems = list_user_stems(scope) |> Enum.take(16)

      case Sampler.quick_load_stems(bank, stems) do
        {:ok, updated_bank} ->
          {:noreply,
           socket
           |> assign(:current_bank, updated_bank)
           |> assign(:selected_pad, nil)}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Pad trigger (feedback from JS hook)
  def handle_event("pad_triggered", %{"pad_id" => _pad_id}, socket) do
    {:noreply, socket}
  end

  # -- MIDI Learn Events --

  def handle_event("toggle_midi_learn", _params, socket) do
    new_mode = !socket.assigns.midi_learn_mode

    if new_mode do
      {:noreply,
       socket
       |> assign(:midi_learn_mode, true)
       |> assign(:midi_learn_target, nil)}
    else
      {:noreply,
       socket
       |> assign(:midi_learn_mode, false)
       |> assign(:midi_learn_target, nil)
       |> push_event("exit_midi_learn", %{})}
    end
  end

  def handle_event("midi_learn_pad", %{"pad-id" => _pad_id, "pad-index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    target = %{type: "pad_trigger", index: idx}

    {:noreply,
     socket
     |> assign(:midi_learn_target, target)
     |> push_event("enter_midi_learn", %{target_type: "pad_trigger", target_index: idx})}
  end

  def handle_event("midi_learn_param", %{"param" => param, "pad-index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    target = %{type: param, index: idx}

    {:noreply,
     socket
     |> assign(:midi_learn_target, target)
     |> push_event("enter_midi_learn", %{target_type: param, target_index: idx})}
  end

  def handle_event(
        "midi_learned",
        %{
          "device_name" => device_name,
          "midi_type" => midi_type_str,
          "channel" => channel,
          "number" => number,
          "target_type" => target_type,
          "target_index" => target_index
        },
        socket
      ) do
    user_id = socket.assigns.current_user_id
    bank = socket.assigns.current_bank

    if user_id && bank do
      midi_type = String.to_existing_atom(midi_type_str)
      action = String.to_existing_atom(target_type)

      attrs = %{
        user_id: user_id,
        device_name: device_name,
        midi_type: midi_type,
        channel: channel,
        number: number,
        action: action,
        bank_id: bank.id,
        parameter_index: target_index,
        params: %{},
        source: "midi_learn"
      }

      SoundForge.MIDI.Mappings.upsert_pad_mapping(attrs)
      mappings = Sampler.bank_midi_mappings(user_id, bank.id)

      {:noreply,
       socket
       |> assign(:midi_learn_mode, false)
       |> assign(:midi_learn_target, nil)
       |> assign(:midi_mappings_count, length(mappings))
       |> push_event("load_midi_mappings", %{mappings: mappings})
       |> push_event("exit_midi_learn", %{})}
    else
      {:noreply, socket}
    end
  end

  # MIDI status from JS
  def handle_event("midi_status", %{"available" => available, "devices" => devices}, socket) do
    {:noreply,
     socket
     |> assign(:midi_available, available)
     |> assign(:midi_devices, devices || [])}
  end

  def handle_event("midi_devices_updated", %{"devices" => devices}, socket) do
    {:noreply, assign(socket, :midi_devices, devices || [])}
  end

  def handle_event("midi_activity", _params, socket) do
    # Flash the MIDI activity indicator briefly.
    # The JS side handles the transient visual flash; server-side just tracks
    # that MIDI is actively receiving data.
    {:noreply, assign(socket, :midi_activity, true)}
  end

  # -- Preset Import Events --

  def handle_event("start_import_preset", _params, socket) do
    {:noreply,
     socket
     |> assign(:importing_preset, true)
     |> assign(:import_error, nil)
     |> assign(:import_success, nil)}
  end

  def handle_event("cancel_import_preset", _params, socket) do
    {:noreply, assign(socket, :importing_preset, false)}
  end

  def handle_event("validate_preset", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_preset_entry", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :preset_file, ref)}
  end

  def handle_event("upload_preset", _params, socket) do
    user_id = socket.assigns.current_user_id

    result =
      consume_uploaded_entries(socket, :preset_file, fn %{path: path}, entry ->
        file_binary = File.read!(path)
        filename = entry.client_name

        case Sampler.import_preset(user_id, file_binary, filename) do
          {:ok, bank} -> {:ok, bank}
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    case result do
      [{:error, reason}] ->
        {:noreply,
         socket
         |> assign(:import_error, reason)
         |> assign(:import_success, nil)}

      [%SoundForge.Sampler.Bank{} = bank] ->
        banks = Sampler.list_banks(user_id)
        mappings = Sampler.bank_midi_mappings(user_id, bank.id)

        {:noreply,
         socket
         |> assign(:banks, banks)
         |> assign(:current_bank, bank)
         |> assign(:selected_pad, nil)
         |> assign(:importing_preset, false)
         |> assign(:import_error, nil)
         |> assign(:import_success, "Imported '#{bank.name}' with #{length(bank.pads)} pads.")
         |> assign(:midi_mappings_count, length(mappings))
         |> push_event("load_midi_mappings", %{mappings: mappings})}

      _ ->
        {:noreply, assign(socket, :import_error, "No file selected.")}
    end
  end

  # -- Private Helpers --

  defp reload_bank(socket, updated_pad) do
    bank = Sampler.get_bank!(socket.assigns.current_bank.id)

    selected =
      if socket.assigns.selected_pad && socket.assigns.selected_pad.id == updated_pad.id,
        do: updated_pad,
        else: socket.assigns.selected_pad

    socket
    |> assign(:current_bank, bank)
    |> assign(:selected_pad, selected)
  end

  defp bank_pads(nil), do: []

  defp bank_pads(%{pads: pads}) when is_list(pads) do
    pads |> Enum.sort_by(& &1.index)
  end

  defp bank_pads(_), do: []

  defp list_user_stems(nil), do: []

  defp list_user_stems(scope) do
    import Ecto.Query

    SoundForge.Music.Stem
    |> join(:inner, [s], t in SoundForge.Music.Track, on: s.track_id == t.id)
    |> where([s, t], t.user_id == ^scope.user.id)
    |> where([s, _t], not is_nil(s.file_path))
    |> order_by([s, _t], desc: s.inserted_at)
    |> limit(50)
    |> SoundForge.Repo.all()
    |> SoundForge.Repo.preload(:track)
  end

  defp stem_track_label(%{track: %{title: title}}) when is_binary(title), do: title
  defp stem_track_label(_), do: ""

  defp pad_border_class(_pad, _selected_pad, true), do: "border-yellow-500/50"

  defp pad_border_class(pad, selected_pad, false) do
    cond do
      selected_pad && pad.id == selected_pad.id -> "border-purple-500 ring-1 ring-purple-500/50"
      pad.stem_id -> "border-white/20"
      true -> "border-gray-700"
    end
  end

  defp pad_bg_style(%{stem_id: nil}), do: "background-color: #1f2937"

  defp pad_bg_style(%{color: color}) when is_binary(color) do
    "background-color: #{color}"
  end

  defp pad_bg_style(_), do: "background-color: #1f2937"

  defp pad_display_index(pad, bank) do
    case bank do
      %{pads: pads} when is_list(pads) ->
        case Enum.find_index(pads, &(&1.id == pad.id)) do
          nil -> pad.index + 1
          idx -> idx + 1
        end

      _ ->
        pad.index + 1
    end
  end

  defp pad_color_options do
    ~w(#6b7280 #ef4444 #f97316 #eab308 #22c55e #3b82f6 #8b5cf6 #ec4899 #06b6d4 #a855f7)
  end

  defp format_pitch(pitch) when is_float(pitch) do
    rounded = Float.round(pitch, 0)
    sign = if rounded > 0, do: "+", else: ""
    "#{sign}#{trunc(rounded)}"
  end

  defp format_pitch(pitch) when is_integer(pitch) do
    sign = if pitch > 0, do: "+", else: ""
    "#{sign}#{pitch}"
  end

  defp format_pitch(_), do: "0"

  defp parse_float(val, default) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_float(_, default), do: default

  defp format_learn_target(%{type: type, index: index}) do
    type_label =
      case type do
        "pad_trigger" -> "Pad #{index + 1} trigger"
        "pad_volume" -> "Pad #{index + 1} volume"
        "pad_pitch" -> "Pad #{index + 1} pitch"
        "pad_velocity" -> "Pad #{index + 1} velocity"
        "pad_master_volume" -> "Master volume"
        other -> other
      end

    type_label
  end

  defp format_learn_target(_), do: "unknown"

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_bytes(_), do: ""
end
