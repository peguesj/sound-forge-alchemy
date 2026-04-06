defmodule SoundForgeWeb.Live.Handlers.MidiHandlers do
  @moduledoc """
  MIDI device, monitor, and clock handle_event/handle_info clauses for DashboardLive.

  Extracted via `use SoundForgeWeb.Live.Handlers.MidiHandlers` in DashboardLive.
  All definitions are injected into the calling module's namespace.
  """

  defmacro __using__(_opts) do
    quote do
      # ── Module attributes ────────────────────────────────────────────────

      @bpm_update_interval_ms 5_000
      @note_names ~w(C C# D D# E F F# G G# A A# B)

      # ── MIDI Settings Events ─────────────────────────────────────────────

      def handle_event("show_midi_settings", _params, socket) do
        {:noreply, assign(socket, :show_midi_settings_modal, true)}
      end

      def handle_event("close_midi_settings", _params, socket) do
        {:noreply, assign(socket, :show_midi_settings_modal, false)}
      end

      def handle_event("refresh_midi_devices", _params, socket) do
        devices = safe_list_midi_devices()
        socket = socket |> assign(:midi_devices, devices) |> assign(:refreshing_midi, true)
        Process.send_after(self(), :stop_midi_refresh_spin, 600)
        {:noreply, socket}
      end

      def handle_event("client_midi_devices_updated", %{"devices" => client_devices}, socket) do
        server_physical = safe_list_midi_devices()
        server_names = MapSet.new(server_physical, & &1.name)

        # Web MIDI devices from the browser that aren't already in the server list
        client_only =
          (client_devices || [])
          |> Enum.reject(fn d -> MapSet.member?(server_names, d["name"] || "") end)
          |> Enum.map(fn d ->
            %{
              name: d["name"] || "Unknown",
              physical_name: d["name"] || "Unknown",
              direction: :duplex,
              type: :unknown,
              status: :connected,
              port_count: 1,
              has_input: true,
              has_output: true,
              port_id: d["id"] || "",
              port_ids: [d["id"] || ""],
              ports: [],
              source: :client
            }
          end)

        {:noreply, assign(socket, :midi_devices, server_physical ++ client_only)}
      end

      # ── MIDI Monitor Events ───────────────────────────────────────────────

      def handle_event("toggle_midi_monitor", _params, socket) do
        {:noreply, update(socket, :midi_monitor_open, &(!&1))}
      end

      def handle_event("toggle_midi_monitor_listen", _params, socket) do
        if socket.assigns.midi_monitor_listening do
          for device <- socket.assigns.midi_devices,
              port_id <- (Map.get(device, :port_ids) || [Map.get(device, :port_id, "")]) do
            Phoenix.PubSub.unsubscribe(
              SoundForge.PubSub,
              SoundForge.MIDI.Dispatcher.topic(port_id)
            )
          end

          {:noreply, assign(socket, :midi_monitor_listening, false)}
        else
          devices = SoundForge.MIDI.DeviceManager.list_devices()

          for device <- devices, device.direction in [:input, :duplex] do
            Phoenix.PubSub.subscribe(
              SoundForge.PubSub,
              SoundForge.MIDI.Dispatcher.topic(device.port_id)
            )
          end

          {:noreply, assign(socket, :midi_monitor_listening, true)}
        end
      end

      def handle_event("toggle_midi_tailf", _params, socket) do
        {:noreply, update(socket, :midi_tailf, &(!&1))}
      end

      def handle_event("clear_midi_log", _params, socket) do
        {:noreply, assign(socket, :midi_log, [])}
      end

      # ── MIDI handle_info: Device lifecycle ───────────────────────────────

      def handle_info({:midi_device_connected, device}, socket) do
        devices = safe_list_midi_devices()
        log_entry = midi_log_entry("Device connected: #{device.name}")

        {:noreply,
         socket
         |> assign(:midi_devices, devices)
         |> append_midi_log(log_entry)}
      end

      def handle_info({:midi_device_disconnected, device}, socket) do
        devices = safe_list_midi_devices()
        log_entry = midi_log_entry("Device disconnected: #{device.name}")

        {:noreply,
         socket
         |> assign(:midi_devices, devices)
         |> append_midi_log(log_entry)}
      end

      # ── MIDI handle_info: Clock / Transport ──────────────────────────────

      def handle_info({:bpm_update, bpm}, socket) do
        now = System.monotonic_time(:millisecond)
        last_ms = socket.assigns.last_bpm_ms
        current_bpm = socket.assigns.midi_bpm
        time_ok = now - last_ms >= @bpm_update_interval_ms
        value_changed = current_bpm == nil or abs(bpm - current_bpm) >= 1.0

        if time_ok and value_changed do
          {:noreply,
           socket
           |> assign(:midi_bpm, bpm)
           |> assign(:last_bpm_ms, now)}
        else
          {:noreply, socket}
        end
      end

      def handle_info({:transport, state} = msg, socket) do
        log_entry = midi_log_entry("Transport: #{state}")

        socket =
          socket
          |> assign(:midi_transport, state)
          |> append_midi_log(log_entry)

        if socket.assigns.nav_tab == :dj do
          send_update(SoundForgeWeb.Live.Components.DjTabComponent,
            id: "dj-tab-root",
            midi_event: msg
          )
        end

        {:noreply, socket}
      end

      # ── MIDI handle_info: Actions ─────────────────────────────────────────

      def handle_info({:midi_action, :stem_volume, %{volume: volume, target: target} = params}, socket) do
        log_entry = midi_log_entry("CC -> stem_volume target=#{target} vol=#{Float.round(volume, 2)}")

        socket =
          socket
          |> push_event("midi_fader_update", %{
               target: target,
               volume: volume,
               track_id: Map.get(params, :track_id)
             })
          |> append_midi_log(log_entry)

        {:noreply, socket}
      end

      def handle_info({:midi_action, :play, _params}, socket) do
        send_update(SoundForgeWeb.Live.Components.TransportBarComponent,
          id: "transport-bar",
          midi_event: "transport_play"
        )

        log_entry = midi_log_entry("play -> TransportBar")
        {:noreply, append_midi_log(socket, log_entry)}
      end

      def handle_info({:midi_action, :stop, _params}, socket) do
        send_update(SoundForgeWeb.Live.Components.TransportBarComponent,
          id: "transport-bar",
          midi_event: "transport_stop"
        )

        log_entry = midi_log_entry("stop -> TransportBar")
        {:noreply, append_midi_log(socket, log_entry)}
      end

      def handle_info({:midi_action, :next_track, _params}, socket) do
        send_update(SoundForgeWeb.Live.Components.TransportBarComponent,
          id: "transport-bar",
          midi_event: "transport_next"
        )

        log_entry = midi_log_entry("next_track -> TransportBar")
        {:noreply, append_midi_log(socket, log_entry)}
      end

      def handle_info({:midi_action, :prev_track, _params}, socket) do
        send_update(SoundForgeWeb.Live.Components.TransportBarComponent,
          id: "transport-bar",
          midi_event: "transport_prev"
        )

        log_entry = midi_log_entry("prev_track -> TransportBar")
        {:noreply, append_midi_log(socket, log_entry)}
      end

      def handle_info({:midi_action, action, params}, socket) do
        log_entry = midi_log_entry("#{action}: #{inspect(params, limit: 3)}")
        {:noreply, append_midi_log(socket, log_entry)}
      end

      # ── MIDI handle_info: Raw messages ───────────────────────────────────

      def handle_info({:midi_message, port_id, message}, socket) do
        send_update(SoundForgeWeb.Live.Components.GlobalMidiBarComponent,
          id: "global-midi-bar",
          midi_event: {port_id, message}
        )

        if socket.assigns[:midi_learn_active] do
          send_update(SoundForgeWeb.Live.Components.MidiLearnOverlayComponent,
            id: "midi-learn",
            midi_event: {port_id, message},
            current_user_id: socket.assigns[:current_user_id]
          )
        end

        if socket.assigns.midi_monitor_listening do
          event = build_raw_midi_event(port_id, message)

          send_update(SoundForgeWeb.Live.Components.MidiMonitorComponent,
            id: "midi-monitor",
            new_event: event
          )

          raw_log = [event | socket.assigns.midi_raw_log] |> Enum.take(200)
          {:noreply, assign(socket, :midi_raw_log, raw_log)}
        else
          {:noreply, socket}
        end
      end

      # ── MIDI handle_info: Global bar ─────────────────────────────────────

      def handle_info({:global_midi_bar, :toggle_monitor, open}, socket) do
        {:noreply, assign(socket, :midi_monitor_open, open)}
      end

      def handle_info({:global_midi_bar, :toggle_learn, active}, socket) do
        {:noreply, assign(socket, :midi_learn_active, active)}
      end

      def handle_info({:global_midi_bar, :set_position, pos}, socket) do
        user_id = socket.assigns[:current_user_id]

        if user_id do
          settings =
            SoundForge.Settings.get_user_settings(user_id) ||
              %SoundForge.Accounts.UserSettings{user_id: user_id}

          SoundForge.Settings.update_user_settings(settings, %{midi_bar_position: pos})
        end

        {:noreply, assign(socket, :midi_bar_position, pos)}
      end

      def handle_info({:midi_global_event, port_id, message}, socket) do
        send_update(SoundForgeWeb.Live.Components.GlobalMidiBarComponent,
          id: "global-midi-bar",
          midi_event: {port_id, message}
        )

        {:noreply, socket}
      end

      # ── MIDI handle_info: Misc ────────────────────────────────────────────

      def handle_info(:stop_midi_refresh_spin, socket) do
        {:noreply, assign(socket, :refreshing_midi, false)}
      end

      def handle_info({:reset_midi_activity, component_id}, socket) do
        send_update(SoundForgeWeb.Live.Components.ChromaticPadsComponent,
          id: component_id,
          midi_activity: false
        )

        {:noreply, socket}
      end

      # ── Private: MIDI helpers ─────────────────────────────────────────────

      defp safe_list_midi_devices do
        SoundForge.MIDI.DeviceManager.list_physical_devices()
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

      defp build_raw_midi_event(port_id, message) do
        {type, channel, label, value} = decode_midi_message(message)

        short_port =
          port_id
          |> to_string()
          |> String.split(":")
          |> List.last()
          |> String.slice(0, 8)

        %{
          id: System.unique_integer([:positive]),
          port: short_port,
          type: type,
          channel: channel,
          label: label,
          value: value,
          time: Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
        }
      end

      defp decode_midi_message(%{status: status, data1: d1, data2: d2}) do
        import Bitwise
        channel = (status &&& 0x0F) + 1
        type_nibble = status &&& 0xF0

        case type_nibble do
          0x90 when d2 > 0 -> {"note_on", channel, note_name(d1), d2}
          0x90 -> {"note_off", channel, note_name(d1), 0}
          0x80 -> {"note_off", channel, note_name(d1), d2}
          0xB0 -> {"cc", channel, "CC#{d1}", d2}
          0xA0 -> {"aftertouch", channel, note_name(d1), d2}
          0xD0 -> {"pressure", channel, "CH pressure", d1}
          0xE0 -> {"pitchbend", channel, "PB", d1 + d2 * 128}
          0xC0 -> {"program", channel, "PC#{d1}", 0}
          _ ->
            case status do
              0xF8 -> {"clock", 0, "tick", 0}
              0xFA -> {"clock", 0, "start", 0}
              0xFC -> {"clock", 0, "stop", 0}
              0xFE -> {"clock", 0, "sense", 0}
              0xF0 -> {"sysex", 0, "SysEx", byte_size(d1 || <<>>)}
              _ -> {"other", 0, "0x#{Integer.to_string(status, 16)}", d1}
            end
        end
      end

      defp decode_midi_message(msg) do
        {"raw", 0, inspect(msg, limit: 2), 0}
      end

      defp note_name(midi_note) when is_integer(midi_note) do
        oct = div(midi_note, 12) - 1
        name = Enum.at(@note_names, rem(midi_note, 12))
        "#{name}#{oct}"
      end

      defp note_name(_), do: "?"
    end
  end
end
