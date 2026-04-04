defmodule SoundForgeWeb.Live.Components.MidiLearnOverlayComponent do
  @moduledoc """
  MIDI Learn overlay for any module.

  When active, the page enters learn mode:
  - Highlights all elements with `data-midi-learn-id` attribute
  - User clicks a UI control → that control becomes the "target"
  - User presses a button/key on their MIDI device → next MIDI message is captured
  - The mapping is saved via `SoundForge.MIDI.Mappings.create_mapping/1`
  - Confirms assignment with a brief flash on the control

  ## Integration in parent LiveView

    1. Include: `<.live_component module={MidiLearnOverlayComponent} id="midi-learn" active={@midi_learn_active} module_name="dj" />`
    2. Handle `{:global_midi_bar, :toggle_learn, _}` to toggle `@midi_learn_active`
    3. Subscribe to `GlobalBroadcaster` so MIDI messages flow in

  ## UI control markup

  Any element that should be MIDI-learnable needs:
    ```heex
    data-midi-learn-id="transport_play"
    data-midi-learn-label="Play/Pause"
    ```
  """

  use SoundForgeWeb, :live_component

  alias SoundForge.MIDI.{Mappings, DeviceManager}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:active, false)
     |> assign(:module_name, "dj")
     |> assign(:target_control, nil)
     |> assign(:waiting_for_midi, false)
     |> assign(:last_assignment, nil)
     |> assign(:pending_device, nil)
     |> assign(:current_user_id, nil)}
  end

  @impl true
  def update(%{midi_event: {port_id, msg}} = _assigns, socket) do
    if socket.assigns.active and socket.assigns.waiting_for_midi and socket.assigns.target_control do
      target = socket.assigns.target_control
      user_id = socket.assigns.current_user_id

      device_name =
        case DeviceManager.get_device_by_port(port_id) do
          %{name: name} -> name
          _ -> port_id
        end

      action = control_to_action(target, socket.assigns.module_name)

      mapping_attrs = %{
        user_id: user_id,
        device_name: device_name,
        midi_type: midi_type_atom(msg),
        channel: Map.get(msg, :channel, 0),
        number: Map.get(msg, :data1, 0),
        action: action,
        source: "learn"
      }

      assignment =
        case Mappings.create_mapping(mapping_attrs) do
          {:ok, _mapping} ->
            %{control: target, device: device_name, action: action, success: true}

          {:error, _} ->
            # Try upsert (update existing binding for this control)
            case Mappings.get_mapping_for_control(user_id, device_name, Map.get(msg, :data1, 0)) do
              nil -> %{control: target, device: device_name, action: action, success: false}
              existing ->
                Mappings.update_mapping(existing, %{action: action})
                %{control: target, device: device_name, action: action, success: true}
            end
        end

      {:ok,
       socket
       |> assign(:waiting_for_midi, false)
       |> assign(:target_control, nil)
       |> assign(:last_assignment, assignment)
       |> push_event("midi_learn_assigned", %{
         control_id: target["id"],
         device: device_name,
         action: action,
         success: assignment.success
       })}
    else
      {:ok, socket}
    end
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:active, assigns[:active] || false)
     |> assign(:module_name, assigns[:module_name] || socket.assigns.module_name)
     |> assign(:current_user_id, assigns[:current_user_id] || socket.assigns.current_user_id)}
  end

  @impl true
  def handle_event("select_control", %{"id" => control_id, "label" => label}, socket) do
    if socket.assigns.active do
      target = %{"id" => control_id, "label" => label}
      {:noreply,
       socket
       |> assign(:target_control, target)
       |> assign(:waiting_for_midi, true)
       |> push_event("midi_learn_waiting", %{control_id: control_id})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_learn", _params, socket) do
    {:noreply,
     socket
     |> assign(:waiting_for_midi, false)
     |> assign(:target_control, nil)
     |> push_event("midi_learn_cancelled", %{})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"midi-learn-overlay-#{@module_name}"} phx-hook="MidiLearnOverlay" data-active={to_string(@active)}>
      <%!-- Dim overlay when active --%>
      <div
        :if={@active}
        class="fixed inset-0 bg-black/30 z-30 pointer-events-none"
        style="backdrop-filter: blur(1px);"
      ></div>

      <%!-- Learn mode banner --%>
      <div
        :if={@active}
        class="fixed top-10 left-1/2 -translate-x-1/2 z-50 flex items-center gap-3 px-4 py-2 bg-yellow-500 text-black rounded-xl shadow-2xl text-sm font-bold"
      >
        <div class="w-2 h-2 rounded-full bg-black animate-pulse"></div>
        <%= if @waiting_for_midi and @target_control do %>
          Press a button on your MIDI controller to assign "<%= @target_control["label"] %>"
          <button
            phx-click="cancel_learn"
            phx-target={@myself}
            class="ml-2 px-2 py-0.5 bg-black/20 rounded text-xs hover:bg-black/30"
          >
            Cancel
          </button>
        <% else %>
          MIDI Learn active — click any highlighted control
        <% end %>
      </div>

      <%!-- Assignment confirmation flash --%>
      <%= if @last_assignment do %>
        <div
          id="midi-learn-confirm"
          class={[
            "fixed top-20 left-1/2 -translate-x-1/2 z-50 px-4 py-2 rounded-lg text-sm font-semibold shadow-xl",
            if(@last_assignment.success, do: "bg-green-600 text-white", else: "bg-red-600 text-white")
          ]}
          phx-remove={JS.hide(transition: {"ease-out duration-500", "opacity-100", "opacity-0"})}
        >
          <%= if @last_assignment.success do %>
            Assigned: {@last_assignment.device} → {@last_assignment.control["label"]}
          <% else %>
            Assignment failed — try again
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # -- Private --

  defp control_to_action(%{"id" => id}, module_name) do
    action_map = %{
      # DJ module
      "transport_play" => :dj_play,
      "transport_stop" => :dj_cue,
      "deck_1_play" => :dj_play,
      "deck_2_play" => :dj_play,
      "hot_cue_a" => :dj_hot_cue_a,
      "hot_cue_b" => :dj_hot_cue_b,
      "hot_cue_c" => :dj_hot_cue_c,
      "hot_cue_d" => :dj_hot_cue_d,
      "crossfader" => :dj_crossfader,
      "deck_1_volume" => :stem_volume,
      "deck_2_volume" => :stem_volume,
      # DAW module
      "daw_play" => :play,
      "daw_stop" => :stop,
      "daw_record" => :daw_record,
      "daw_track_volume" => :stem_volume,
      # Library / general
      "lib_next" => :next_track,
      "lib_prev" => :prev_track,
      "lib_play" => :play,
      "lib_stop" => :stop,
      "master_volume" => :stem_volume
    }

    full_key = "#{module_name}_#{id}"

    Map.get(action_map, id) || Map.get(action_map, full_key) || String.to_atom(id)
  end

  defp midi_type_atom(%{status: s}) when s in 0x80..0x9F, do: :note
  defp midi_type_atom(%{status: s}) when s in 0xB0..0xBF, do: :cc
  defp midi_type_atom(%{status: s}) when s in 0xD0..0xDF, do: :aftertouch
  defp midi_type_atom(%{status: s}) when s in 0xE0..0xEF, do: :pitchbend
  defp midi_type_atom(_), do: :cc
end
