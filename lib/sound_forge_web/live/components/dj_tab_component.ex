defmodule SoundForgeWeb.Live.Components.DjTabComponent do
  @moduledoc """
  DJ dual-deck component rendered inline within the dashboard.

  Provides two independent audio decks with WaveSurfer waveform displays,
  transport controls, BPM display, crossfader, cue points, loops, pitch,
  sync, and the virtual controller -- all within a LiveComponent.

  PubSub messages (MIDI clock, transport) are forwarded from the parent
  DashboardLive via `send_update/3`.
  """
  use SoundForgeWeb, :live_component

  alias SoundForge.Music
  alias SoundForge.DJ
  alias SoundForge.DJ.{Presets, Timecode}
  alias SoundForge.MIDI.Mappings
  alias SoundForge.Audio.Prefetch

  # -- Lifecycle --

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:tracks, [])
     |> assign(:crossfader, 0)
     |> assign(:crossfader_curve, "linear")
     |> assign(:deck_1_volume, 100)
     |> assign(:deck_2_volume, 100)
     |> assign(:deck_1, empty_deck_state())
     |> assign(:deck_2, empty_deck_state())
     |> assign(:deck_1_cue_points, [])
     |> assign(:deck_2_cue_points, [])
     |> assign(:preset_section_open, false)
     |> assign(:initialized, false)
     |> allow_upload(:preset_file,
       accept: ~w(.tsi .touchosc),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def update(%{midi_event: {:bpm_update, external_bpm}}, socket) do
    socket =
      Enum.reduce([{:deck_1, 1}, {:deck_2, 2}], socket, fn {deck_key, deck_number}, acc ->
        deck = Map.get(acc.assigns, deck_key)

        if deck.midi_sync && deck.track && deck.tempo_bpm > 0 do
          needed_pitch = (external_bpm / deck.tempo_bpm - 1.0) * 100.0
          clamped_pitch = needed_pitch |> max(-8.0) |> min(8.0) |> Float.round(1)
          updated_deck = %{deck | pitch_adjust: clamped_pitch}

          acc
          |> assign(deck_key, updated_deck)
          |> push_event("set_pitch", %{deck: deck_number, value: clamped_pitch})
        else
          acc
        end
      end)

    {:ok, socket}
  end

  def update(%{midi_event: {:transport, transport_event}}, socket) do
    socket =
      Enum.reduce([{:deck_1, 1}, {:deck_2, 2}], socket, fn {deck_key, deck_number}, acc ->
        deck = Map.get(acc.assigns, deck_key)

        if deck.midi_sync && deck.track do
          case transport_event do
            event when event in [:start, :continue] ->
              updated_deck = %{deck | playing: true}

              acc
              |> assign(deck_key, updated_deck)
              |> push_event("play_deck", %{deck: deck_number, playing: true})

            :stop ->
              updated_deck = %{deck | playing: false}

              acc
              |> assign(deck_key, updated_deck)
              |> push_event("play_deck", %{deck: deck_number, playing: false})

            _ ->
              acc
          end
        else
          acc
        end
      end)

    {:ok, socket}
  end

  def update(%{keydown: %{"key" => "z"}}, socket) do
    new_value = max(socket.assigns.crossfader - 5, -100)

    {:ok,
     socket
     |> assign(:crossfader, new_value)
     |> push_event("set_crossfader", %{value: new_value})}
  end

  def update(%{keydown: %{"key" => "x"}}, socket) do
    new_value = min(socket.assigns.crossfader + 5, 100)

    {:ok,
     socket
     |> assign(:crossfader, new_value)
     |> push_event("set_crossfader", %{value: new_value})}
  end

  def update(%{keydown: _params}, socket), do: {:ok, socket}

  def update(%{virtual_controller: {:trigger_cue, %{deck: deck_number, slot: slot}}}, socket) do
    cue_points_key = cue_points_assign_key(deck_number)
    cue_points = Map.get(socket.assigns, cue_points_key, [])
    cue = Enum.at(cue_points, slot - 1)

    if cue do
      deck_key = deck_assign_key(deck_number)
      deck = Map.get(socket.assigns, deck_key)
      position = cue.position_ms / 1000

      updated_deck = %{deck | playing: true, position: position}

      {:ok,
       socket
       |> assign(deck_key, updated_deck)
       |> push_event("seek_and_play", %{deck: deck_number, position: position})}
    else
      {:ok, socket}
    end
  end

  def update(assigns, socket) do
    socket = assign(socket, :current_scope, assigns[:current_scope])
    socket = assign(socket, :current_user_id, assigns[:current_user_id])
    socket = assign(socket, :id, assigns[:id])

    if not socket.assigns.initialized do
      tracks = list_user_tracks(assigns[:current_scope])
      {:ok, assign(socket, tracks: tracks, initialized: true)}
    else
      {:ok, socket}
    end
  end

  # -- Events --

  @impl true
  def handle_event("load_track", %{"deck" => deck_str, "track_id" => track_id}, socket) do
    deck_number = String.to_integer(deck_str)
    user_id = socket.assigns[:current_user_id]

    if track_id == "" do
      {:noreply, socket}
    else
      case DJ.load_track_to_deck(user_id, deck_number, track_id) do
        {:ok, session} ->
          track = session.track
          stems = if track, do: track.stems || [], else: []
          audio_urls = build_stem_urls(stems, track)
          pitch = session.pitch_adjust || 0.0

          # Try prefetch cache first for analysis data, fall back to DB
          {tempo, beat_times, structure, loop_points, bar_times, arrangement_markers} =
            case track && Prefetch.get_cached(track.id, :dj) do
              %{} = cached ->
                {cached.tempo, cached.beat_times, cached.structure,
                 cached.loop_points, cached.bar_times, cached.arrangement_markers}

              nil ->
                extract_analysis_data(track)
            end

          deck_state = %{
            track: track,
            playing: false,
            tempo_bpm: session.tempo_bpm || 0.0,
            pitch_adjust: pitch,
            position: 0,
            stems: stems,
            audio_urls: audio_urls,
            loop_active: false,
            loop_start_ms: nil,
            loop_end_ms: nil,
            midi_sync: false,
            structure: structure,
            loop_points: loop_points,
            bar_times: bar_times,
            arrangement_markers: arrangement_markers,
            current_section: nil
          }

          deck_key = deck_assign_key(deck_number)
          cue_points_key = cue_points_assign_key(deck_number)

          cue_points =
            if user_id && track do
              DJ.list_cue_points(track.id, user_id)
            else
              []
            end

          socket =
            socket
            |> assign(deck_key, deck_state)
            |> assign(cue_points_key, cue_points)
            |> push_event("load_deck_audio", %{
              deck: deck_number,
              urls: audio_urls,
              track_title: track && track.title,
              tempo: tempo,
              beat_times: beat_times,
              structure: structure,
              loop_points: loop_points,
              bar_times: bar_times,
              arrangement_markers: arrangement_markers
            })
            |> push_event("set_cue_points", %{
              deck: deck_number,
              cue_points: encode_cue_points(cue_points)
            })
            |> push_event("set_pitch", %{deck: deck_number, value: pitch})

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to load track to deck #{deck_number}")}
      end
    end
  end

  @impl true
  def handle_event("toggle_play", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    if deck.track do
      new_playing = !deck.playing
      updated_deck = %{deck | playing: new_playing}

      transport_event = if new_playing, do: :play, else: :pause

      Phoenix.PubSub.broadcast(
        SoundForge.PubSub,
        "dj:transport",
        {:dj_transport, deck_number, transport_event}
      )

      socket =
        socket
        |> assign(deck_key, updated_deck)
        |> push_event("play_deck", %{deck: deck_number, playing: new_playing})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("crossfader", %{"value" => value_str}, socket) do
    value = String.to_integer(value_str)

    socket =
      socket
      |> assign(:crossfader, value)
      |> push_event("set_crossfader", %{value: value})

    {:noreply, socket}
  end

  @impl true
  def handle_event("time_update", %{"deck" => deck_str, "position" => position}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    updated_deck = %{deck | position: position}
    {:noreply, assign(socket, deck_key, updated_deck)}
  end

  @impl true
  def handle_event("deck_stopped", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    updated_deck = %{deck | playing: false, position: 0}
    {:noreply, assign(socket, deck_key, updated_deck)}
  end

  @impl true
  def handle_event("set_crossfader_curve", %{"curve" => curve}, socket)
      when curve in ["linear", "equal_power", "sharp"] do
    socket =
      socket
      |> assign(:crossfader_curve, curve)
      |> push_event("set_crossfader_curve", %{curve: curve})

    {:noreply, socket}
  end

  def handle_event("set_crossfader_curve", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_deck_volume", %{"deck" => deck_str, "level" => level_str}, socket) do
    deck_number = String.to_integer(deck_str)
    level = String.to_integer(level_str) |> max(0) |> min(100)
    volume_key = if deck_number == 1, do: :deck_1_volume, else: :deck_2_volume

    socket =
      socket
      |> assign(volume_key, level)
      |> push_event("set_deck_volume", %{deck: deck_number, level: level})

    {:noreply, socket}
  end

  @impl true
  def handle_event("jog_scratch", %{"deck" => deck_str, "delta" => delta}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    if deck.track do
      offset = delta * 0.01
      new_pos = max(0.0, deck.position + offset)
      updated_deck = %{deck | position: new_pos}

      socket =
        socket
        |> assign(deck_key, updated_deck)
        |> push_event("seek_deck", %{deck: deck_number, position: new_pos})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("jog_cue_press", %{"deck" => _deck_str}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("jog_cue_release", %{"deck" => _deck_str}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_midi_sync", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    updated_deck = %{deck | midi_sync: !deck.midi_sync}
    {:noreply, assign(socket, deck_key, updated_deck)}
  end

  # -- Loop Controls --

  @impl true
  def handle_event("loop_in", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    if deck.track do
      position_ms = trunc(deck.position * 1000)
      quantized_ms = quantize_to_beat(position_ms, deck.tempo_bpm)
      updated_deck = %{deck | loop_start_ms: quantized_ms, loop_end_ms: nil, loop_active: false}

      socket =
        socket
        |> assign(deck_key, updated_deck)
        |> push_event("set_loop", %{
          deck: deck_number,
          loop_start_ms: quantized_ms,
          loop_end_ms: nil,
          active: false
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("loop_out", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    if deck.track && deck.loop_start_ms do
      position_ms = trunc(deck.position * 1000)
      quantized_ms = quantize_to_beat(position_ms, deck.tempo_bpm)
      loop_end = max(quantized_ms, deck.loop_start_ms + 1)
      updated_deck = %{deck | loop_end_ms: loop_end, loop_active: true}

      user_id = socket.assigns[:current_user_id]
      persist_loop(user_id, deck_number, deck.loop_start_ms, loop_end)

      socket =
        socket
        |> assign(deck_key, updated_deck)
        |> push_event("set_loop", %{
          deck: deck_number,
          loop_start_ms: deck.loop_start_ms,
          loop_end_ms: loop_end,
          active: true
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("loop_size", %{"deck" => deck_str, "beats" => beats_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    beats = parse_beats(beats_str)

    if deck.track && deck.tempo_bpm > 0 do
      loop_start =
        deck.loop_start_ms || quantize_to_beat(trunc(deck.position * 1000), deck.tempo_bpm)

      loop_length_ms = trunc(beats * (60_000 / deck.tempo_bpm))
      loop_end = loop_start + loop_length_ms

      updated_deck = %{deck | loop_start_ms: loop_start, loop_end_ms: loop_end, loop_active: true}

      user_id = socket.assigns[:current_user_id]
      persist_loop(user_id, deck_number, loop_start, loop_end)

      socket =
        socket
        |> assign(deck_key, updated_deck)
        |> push_event("set_loop", %{
          deck: deck_number,
          loop_start_ms: loop_start,
          loop_end_ms: loop_end,
          active: true
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("loop_toggle", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    if deck.loop_start_ms && deck.loop_end_ms do
      new_active = !deck.loop_active
      updated_deck = %{deck | loop_active: new_active}

      socket =
        socket
        |> assign(deck_key, updated_deck)
        |> push_event("set_loop", %{
          deck: deck_number,
          loop_start_ms: deck.loop_start_ms,
          loop_end_ms: deck.loop_end_ms,
          active: new_active
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # -- Smart Loop (from analysis) --

  @impl true
  def handle_event("set_smart_loop", %{"deck" => deck_str, "loop-idx" => idx_str}, socket) do
    deck_number = String.to_integer(deck_str)
    idx = String.to_integer(idx_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    loop_points = deck.loop_points || []
    lp = Enum.at(loop_points, idx)

    if deck.track && lp do
      loop_start = lp["loop_start_ms"]
      loop_end = lp["loop_end_ms"]

      updated_deck = %{deck | loop_start_ms: loop_start, loop_end_ms: loop_end, loop_active: true}

      user_id = socket.assigns[:current_user_id]
      persist_loop(user_id, deck_number, loop_start, loop_end)

      socket =
        socket
        |> assign(deck_key, updated_deck)
        |> push_event("set_loop", %{
          deck: deck_number,
          loop_start_ms: loop_start,
          loop_end_ms: loop_end,
          active: true
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # -- Section Skip --

  @impl true
  def handle_event("skip_section", %{"deck" => deck_str, "direction" => direction}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    segments = get_in(deck.structure || %{}, ["segments"]) || []

    if deck.track && length(segments) > 0 do
      current_pos = deck.position
      target_pos = find_section_boundary(segments, current_pos, direction)

      if target_pos do
        updated_deck = %{deck | position: target_pos, playing: true}

        socket =
          socket
          |> assign(deck_key, updated_deck)
          |> push_event("seek_and_play", %{deck: deck_number, position: target_pos})

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # -- Pitch / Tempo Controls --

  @impl true
  def handle_event("set_pitch", %{"deck" => deck_str, "value" => value_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    pitch =
      case Float.parse(to_string(value_str)) do
        {val, _} -> (val / 10.0) |> max(-8.0) |> min(8.0)
        :error -> 0.0
      end

    updated_deck = %{deck | pitch_adjust: pitch}
    user_id = socket.assigns[:current_user_id]
    persist_pitch(user_id, deck_number, pitch)

    socket =
      socket
      |> assign(deck_key, updated_deck)
      |> push_event("set_pitch", %{deck: deck_number, value: pitch})

    {:noreply, socket}
  end

  @impl true
  def handle_event("pitch_reset", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    updated_deck = %{deck | pitch_adjust: 0.0}
    user_id = socket.assigns[:current_user_id]
    persist_pitch(user_id, deck_number, 0.0)

    socket =
      socket
      |> assign(deck_key, updated_deck)
      |> push_event("set_pitch", %{deck: deck_number, value: 0.0})

    {:noreply, socket}
  end

  @impl true
  def handle_event("sync_deck", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    other_number = if deck_number == 1, do: 2, else: 1

    deck_key = deck_assign_key(deck_number)
    other_key = deck_assign_key(other_number)
    deck = Map.get(socket.assigns, deck_key)
    other = Map.get(socket.assigns, other_key)

    if deck.track && other.track && deck.tempo_bpm > 0 && other.tempo_bpm > 0 do
      other_adjusted_bpm = other.tempo_bpm * (1.0 + other.pitch_adjust / 100.0)
      needed_pitch = (other_adjusted_bpm / deck.tempo_bpm - 1.0) * 100.0
      clamped_pitch = needed_pitch |> max(-8.0) |> min(8.0) |> Float.round(1)

      updated_deck = %{deck | pitch_adjust: clamped_pitch}
      user_id = socket.assigns[:current_user_id]
      persist_pitch(user_id, deck_number, clamped_pitch)

      socket =
        socket
        |> assign(deck_key, updated_deck)
        |> push_event("set_pitch", %{deck: deck_number, value: clamped_pitch})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("master_sync", _params, socket) do
    deck_1 = socket.assigns.deck_1
    deck_2 = socket.assigns.deck_2

    if deck_1.track && deck_2.track && deck_1.tempo_bpm > 0 && deck_2.tempo_bpm > 0 do
      avg_bpm = (deck_1.tempo_bpm + deck_2.tempo_bpm) / 2.0

      pitch_1 =
        ((avg_bpm / deck_1.tempo_bpm - 1.0) * 100.0) |> max(-8.0) |> min(8.0) |> Float.round(1)

      pitch_2 =
        ((avg_bpm / deck_2.tempo_bpm - 1.0) * 100.0) |> max(-8.0) |> min(8.0) |> Float.round(1)

      updated_1 = %{deck_1 | pitch_adjust: pitch_1}
      updated_2 = %{deck_2 | pitch_adjust: pitch_2}

      user_id = socket.assigns[:current_user_id]
      persist_pitch(user_id, 1, pitch_1)
      persist_pitch(user_id, 2, pitch_2)

      socket =
        socket
        |> assign(:deck_1, updated_1)
        |> assign(:deck_2, updated_2)
        |> push_event("set_pitch", %{deck: 1, value: pitch_1})
        |> push_event("set_pitch", %{deck: 2, value: pitch_2})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # -- Cue Point Controls --

  @impl true
  def handle_event("set_cue", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    cue_points_key = cue_points_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    user_id = socket.assigns[:current_user_id]
    existing_cues = Map.get(socket.assigns, cue_points_key)

    if deck.track && user_id && length(existing_cues) < 8 do
      position_ms = trunc(deck.position * 1000)
      color = Enum.at(cue_point_colors(), length(existing_cues))

      case DJ.create_cue_point(%{
             track_id: deck.track.id,
             user_id: user_id,
             position_ms: position_ms,
             cue_type: :hot,
             color: color,
             label: "Cue #{length(existing_cues) + 1}"
           }) do
        {:ok, cue_point} ->
          updated_cues = existing_cues ++ [cue_point]

          socket =
            socket
            |> assign(cue_points_key, updated_cues)
            |> push_event("set_cue_points", %{
              deck: deck_number,
              cue_points: encode_cue_points(updated_cues)
            })

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to set cue point")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("trigger_cue", %{"deck" => deck_str, "cue_id" => cue_id}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    if deck.track do
      case DJ.get_cue_point(cue_id) do
        %DJ.CuePoint{} = cue_point ->
          position_sec = cue_point.position_ms / 1000
          updated_deck = %{deck | playing: true, position: position_sec}

          socket =
            socket
            |> assign(deck_key, updated_deck)
            |> push_event("seek_and_play", %{deck: deck_number, position: position_sec})

          {:noreply, socket}

        nil ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_cue", %{"deck" => deck_str, "cue_id" => cue_id}, socket) do
    deck_number = String.to_integer(deck_str)
    cue_points_key = cue_points_assign_key(deck_number)
    existing_cues = Map.get(socket.assigns, cue_points_key)

    case DJ.get_cue_point(cue_id) do
      %DJ.CuePoint{} = cue_point ->
        case DJ.delete_cue_point(cue_point) do
          {:ok, _} ->
            updated_cues = Enum.reject(existing_cues, &(&1.id == cue_id))

            socket =
              socket
              |> assign(cue_points_key, updated_cues)
              |> push_event("set_cue_points", %{
                deck: deck_number,
                cue_points: encode_cue_points(updated_cues)
              })

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete cue point")}
        end

      nil ->
        {:noreply, socket}
    end
  end

  # -- Preset Upload --

  @impl true
  def handle_event("toggle_preset_section", _params, socket) do
    {:noreply, assign(socket, :preset_section_open, !socket.assigns.preset_section_open)}
  end

  @impl true
  def handle_event("validate_preset", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("upload_preset", _params, socket) do
    user_id = socket.assigns[:current_user_id]

    results =
      consume_uploaded_entries(socket, :preset_file, fn %{path: path}, entry ->
        binary = File.read!(path)
        ext = Path.extname(entry.client_name) |> String.downcase()

        case ext do
          ".tsi" -> Presets.parse_tsi(binary, user_id)
          ".touchosc" -> Presets.parse_touchosc(binary, user_id)
          _ -> {:error, "Unsupported file type: #{ext}"}
        end
      end)

    case results do
      [{:ok, mapping_attrs}] ->
        count =
          Enum.count(mapping_attrs, fn attrs ->
            case Mappings.create_mapping(attrs) do
              {:ok, _} -> true
              {:error, _} -> false
            end
          end)

        {:noreply,
         socket
         |> assign(:preset_section_open, false)
         |> put_flash(:info, "Imported #{count} mapping(s) from preset")}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, "Preset import failed: #{reason}")}

      _ ->
        {:noreply, put_flash(socket, :error, "No preset file uploaded")}
    end
  end

  # -- Template --

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="dj-tab"
      phx-hook="DjDeck"
      class="p-4 md:p-6"
      phx-target={@myself}
    >
      <div class="max-w-7xl mx-auto">
        <%!-- Decks Layout --%>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 md:gap-6">
          <%!-- DECK 1 --%>
          <.deck_panel
            deck_number={1}
            deck={@deck_1}
            tracks={@tracks}
            volume={@deck_1_volume}
            cue_points={@deck_1_cue_points}
            midi_sync={@deck_1.midi_sync}
            structure={@deck_1.structure || %{}}
            loop_points={@deck_1.loop_points || []}
            bar_times={@deck_1.bar_times || []}
            arrangement_markers={@deck_1.arrangement_markers || []}
            myself={@myself}
          />

          <%!-- DECK 2 --%>
          <.deck_panel
            deck_number={2}
            deck={@deck_2}
            tracks={@tracks}
            volume={@deck_2_volume}
            cue_points={@deck_2_cue_points}
            midi_sync={@deck_2.midi_sync}
            structure={@deck_2.structure || %{}}
            loop_points={@deck_2.loop_points || []}
            bar_times={@deck_2.bar_times || []}
            arrangement_markers={@deck_2.arrangement_markers || []}
            myself={@myself}
          />
        </div>

        <%!-- Crossfader --%>
        <div class="mt-6 bg-gray-900 rounded-xl p-4">
          <div class="flex items-center gap-4">
            <span class="text-sm font-semibold text-cyan-400 w-16 text-center">DECK 1</span>
            <div class="flex-1 flex flex-col items-center">
              <label class="text-xs text-gray-500 mb-2 uppercase tracking-wider">Crossfader</label>
              <input
                type="range"
                min="-100"
                max="100"
                value={@crossfader}
                phx-change="crossfader"
                phx-target={@myself}
                name="value"
                aria-label="Crossfader"
                class="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-purple-500"
              />
              <div class="flex justify-between w-full mt-1">
                <span class="text-xs text-gray-600">A</span>
                <span class="text-xs text-gray-600">|</span>
                <span class="text-xs text-gray-600">B</span>
              </div>
              <span class="text-xs text-gray-600 mt-1">Z / X to nudge</span>
            </div>
            <span class="text-sm font-semibold text-orange-400 w-16 text-center">DECK 2</span>
          </div>

          <%!-- Crossfader Curve Selector --%>
          <div class="flex items-center justify-center gap-3 mt-3 pt-3 border-t border-gray-700/50">
            <span class="text-xs text-gray-500 uppercase tracking-wider mr-2">Curve</span>
            <button
              :for={curve <- [{"linear", "Linear"}, {"equal_power", "Equal Power"}, {"sharp", "Sharp"}]}
              phx-click="set_crossfader_curve"
              phx-target={@myself}
              phx-value-curve={elem(curve, 0)}
              class={"px-3 py-1 text-xs rounded-md font-medium transition-colors " <>
                if(@crossfader_curve == elem(curve, 0),
                  do: "bg-purple-600 text-white",
                  else: "bg-gray-700 text-gray-400 hover:bg-gray-600 hover:text-gray-300"
                )}
            >
              {elem(curve, 1)}
            </button>
          </div>

          <%!-- Master Sync --%>
          <div class="flex items-center justify-center mt-3 pt-3 border-t border-gray-700/50">
            <button
              phx-click="master_sync"
              phx-target={@myself}
              disabled={is_nil(@deck_1.track) || is_nil(@deck_2.track) || @deck_1.tempo_bpm <= 0 || @deck_2.tempo_bpm <= 0}
              class={"px-6 py-2 text-sm font-bold rounded-lg transition-colors " <>
                if(is_nil(@deck_1.track) || is_nil(@deck_2.track) || @deck_1.tempo_bpm <= 0 || @deck_2.tempo_bpm <= 0,
                  do: "bg-gray-700 text-gray-600 cursor-not-allowed",
                  else: "bg-yellow-600 text-white hover:bg-yellow-500 ring-1 ring-yellow-400/30"
                )}
            >
              MASTER SYNC
            </button>
          </div>
        </div>

        <%!-- Import Preset Section --%>
        <div class="mt-4 bg-gray-900 rounded-xl border border-gray-700/50">
          <button
            phx-click="toggle_preset_section"
            phx-target={@myself}
            class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-gray-300 hover:text-white transition-colors"
          >
            <span class="flex items-center gap-2">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" />
              </svg>
              Import Preset
            </span>
            <svg
              class={"w-4 h-4 transition-transform " <> if(@preset_section_open, do: "rotate-180", else: "")}
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
            </svg>
          </button>

          <div :if={@preset_section_open} class="px-4 pb-4 border-t border-gray-700/50">
            <p class="text-xs text-gray-500 mt-3 mb-3">
              Upload a Traktor .tsi or TouchOSC .touchosc preset file to import MIDI/OSC mappings.
            </p>
            <form phx-submit="upload_preset" phx-change="validate_preset" phx-target={@myself}>
              <div class="flex items-center gap-3">
                <div class="flex-1">
                  <.live_file_input upload={@uploads.preset_file} class="
                    block w-full text-sm text-gray-400
                    file:mr-4 file:py-2 file:px-4
                    file:rounded-lg file:border-0
                    file:text-sm file:font-semibold
                    file:bg-purple-600 file:text-white
                    hover:file:bg-purple-500
                    file:cursor-pointer
                  " />
                </div>
                <button
                  type="submit"
                  class="px-4 py-2 bg-purple-600 text-white text-sm font-medium rounded-lg hover:bg-purple-500 transition-colors disabled:bg-gray-700 disabled:text-gray-500 disabled:cursor-not-allowed"
                  disabled={@uploads.preset_file.entries == []}
                >
                  Import
                </button>
              </div>

              <%!-- Upload errors --%>
              <div :for={entry <- @uploads.preset_file.entries} class="mt-2">
                <div :for={err <- upload_errors(@uploads.preset_file, entry)} class="text-xs text-red-400">
                  {upload_error_to_string(err)}
                </div>
              </div>
            </form>
          </div>
        </div>

        <%!-- Virtual Controller --%>
        <.live_component
          module={SoundForgeWeb.Live.Components.VirtualController}
          id="virtual-controller"
          deck_1_cue_points={@deck_1_cue_points}
          deck_2_cue_points={@deck_2_cue_points}
        />
      </div>
    </div>
    """
  end

  # -- Sub-Components --

  attr :deck_number, :integer, required: true
  attr :deck, :map, required: true
  attr :tracks, :list, required: true
  attr :volume, :integer, required: true
  attr :cue_points, :list, required: true
  attr :midi_sync, :boolean, default: false
  attr :structure, :map, default: %{}
  attr :loop_points, :list, default: []
  attr :bar_times, :list, default: []
  attr :arrangement_markers, :list, default: []
  attr :myself, :any, required: true

  defp deck_panel(assigns) do
    deck_color = if assigns.deck_number == 1, do: "cyan", else: "orange"
    assigns = assign(assigns, :deck_color, deck_color)

    ~H"""
    <div class={"bg-gray-900 rounded-xl p-4 border border-gray-700/50 " <>
      if(@deck.playing, do: "ring-1 ring-#{@deck_color}-500/30", else: "")}>
      <%!-- Deck Label --%>
      <div class="flex items-center justify-between mb-3">
        <span class={"text-sm font-bold tracking-wider " <>
          if(@deck_number == 1, do: "text-cyan-400", else: "text-orange-400")}>
          DECK {@deck_number}
        </span>
        <span class={"text-xs px-2 py-0.5 rounded-full " <>
          if(@deck.playing, do: "bg-green-500/20 text-green-400", else: "bg-gray-700 text-gray-500")}>
          {if @deck.playing, do: "PLAYING", else: "STOPPED"}
        </span>
      </div>

      <%!-- Track Title --%>
      <div class="mb-3">
        <p class="text-white font-medium truncate text-lg">
          {if @deck.track, do: @deck.track.title, else: "Empty"}
        </p>
        <p :if={@deck.track && @deck.track.artist} class="text-gray-400 text-sm truncate">
          {@deck.track.artist}
        </p>
      </div>

      <%!-- Current Section Label --%>
      <div :if={@deck.track && @structure["segments"]} class="mb-2">
        <span class="text-[10px] text-gray-500 uppercase tracking-wider mr-1">Section:</span>
        <span class={"text-xs font-semibold px-2 py-0.5 rounded-full " <>
          if(@deck_number == 1, do: "bg-cyan-900/40 text-cyan-300", else: "bg-orange-900/40 text-orange-300")}>
          {current_section_label(@structure["segments"] || [], @deck.position) || "---"}
        </span>
      </div>

      <%!-- WaveSurfer Waveform --%>
      <div class="relative mb-4">
        <div
          id={"waveform-deck-#{@deck_number}"}
          class="rounded bg-gray-800 border border-gray-700/30 overflow-hidden"
          style="min-height: 110px;"
          data-deck={@deck_number}
          data-structure={Jason.encode!(@structure || %{})}
          data-loop-points={Jason.encode!(@loop_points || [])}
          data-bar-times={Jason.encode!(@bar_times || [])}
          data-arrangement-markers={Jason.encode!(@arrangement_markers || [])}
        >
        </div>
        <div
          :if={is_nil(@deck.track)}
          class="absolute inset-0 flex items-center justify-center text-gray-600 text-sm"
        >
          Load a track to see waveform
        </div>
      </div>

      <%!-- Cue Point Pads --%>
      <div class="mb-4 border border-gray-700/50 rounded-lg p-3">
        <div class="flex items-center justify-between mb-2">
          <span class="text-xs text-gray-500 uppercase tracking-wider font-semibold">Hot Cues</span>
          <button
            phx-click="set_cue"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            disabled={is_nil(@deck.track) || length(@cue_points) >= 8}
            class={"px-3 py-1 text-xs font-bold rounded transition-colors " <>
              if(is_nil(@deck.track) || length(@cue_points) >= 8,
                do: "bg-gray-700 text-gray-600 cursor-not-allowed",
                else: "bg-purple-600 text-white hover:bg-purple-500"
              )}
          >
            SET CUE
          </button>
        </div>
        <div class="grid grid-cols-8 gap-1">
          <%= for slot <- 1..8 do %>
            <% cue = Enum.at(@cue_points, slot - 1) %>
            <%= if cue do %>
              <button
                phx-click="trigger_cue"
                phx-target={@myself}
                phx-value-deck={@deck_number}
                phx-value-cue_id={cue.id}
                class="h-10 rounded text-xs font-bold text-white transition-colors hover:brightness-110 active:scale-95"
                style={"background-color: #{cue.color}"}
                title={cue.label || "Cue #{slot}"}
              >
                {slot}
              </button>
            <% else %>
              <div class="h-10 rounded bg-gray-700/50 flex items-center justify-center text-xs text-gray-600 font-mono">
                {slot}
              </div>
            <% end %>
          <% end %>
        </div>
      </div>

      <%!-- Transport Controls --%>
      <div class="flex items-center gap-3 mb-4">
        <button
          phx-click="toggle_play"
          phx-target={@myself}
          phx-value-deck={@deck_number}
          disabled={is_nil(@deck.track)}
          aria-label={if @deck.playing, do: "Pause deck #{@deck_number}", else: "Play deck #{@deck_number}"}
          class={"w-12 h-12 rounded-full flex items-center justify-center transition-colors " <>
            if(is_nil(@deck.track),
              do: "bg-gray-700 text-gray-600 cursor-not-allowed",
              else: "bg-purple-600 hover:bg-purple-500 text-white"
            )}
        >
          <svg :if={!@deck.playing} class="w-5 h-5 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
            <path d="M8 5v14l11-7z" />
          </svg>
          <svg :if={@deck.playing} class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
            <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
          </svg>
        </button>

        <span class="text-sm text-gray-400 font-mono">
          {format_position(@deck.position)}
        </span>
        <span class="text-xs text-gray-500 font-mono ml-1" title="SMPTE timecode (30fps)">
          {Timecode.ms_to_smpte(@deck.position * 1000)}
        </span>

        <button
          phx-click="toggle_midi_sync"
          phx-target={@myself}
          phx-value-deck={@deck_number}
          class={"px-2 py-1 text-xs font-bold rounded transition-colors ml-2 " <>
            if(@midi_sync,
              do: "bg-green-600 text-white ring-1 ring-green-400/50",
              else: "bg-gray-700 text-gray-400 hover:bg-gray-600 hover:text-gray-300"
            )}
          title="Sync deck to external MIDI clock"
        >
          MIDI SYNC
        </button>

        <%!-- Section Skip Buttons --%>
        <div :if={@structure["segments"]} class="flex items-center gap-0.5 ml-2">
          <button
            phx-click="skip_section"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            phx-value-direction="back"
            disabled={is_nil(@deck.track)}
            class={"px-1.5 py-1 text-xs font-bold rounded transition-colors " <>
              if(is_nil(@deck.track),
                do: "bg-gray-700 text-gray-600 cursor-not-allowed",
                else: "bg-gray-700 text-gray-300 hover:bg-gray-600"
              )}
            title="Previous section"
          >
            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 24 24"><path d="M6 6h2v12H6zm3.5 6l8.5 6V6z" transform="scale(-1,1) translate(-24,0)" /></svg>
          </button>
          <button
            phx-click="skip_section"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            phx-value-direction="forward"
            disabled={is_nil(@deck.track)}
            class={"px-1.5 py-1 text-xs font-bold rounded transition-colors " <>
              if(is_nil(@deck.track),
                do: "bg-gray-700 text-gray-600 cursor-not-allowed",
                else: "bg-gray-700 text-gray-300 hover:bg-gray-600"
              )}
            title="Next section"
          >
            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 24 24"><path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z" /></svg>
          </button>
        </div>

        <div class="ml-auto flex items-center gap-1.5">
          <span class="text-xs text-gray-500 uppercase">BPM</span>
          <span class={"text-lg font-bold font-mono " <>
            if(@deck.tempo_bpm > 0, do: "text-white", else: "text-gray-600")}>
            {format_bpm(@deck.tempo_bpm)}
          </span>
        </div>
      </div>

      <%!-- Pitch / Tempo Control --%>
      <div class="mb-4 border border-gray-700/50 rounded-lg p-3">
        <div class="flex items-center justify-between mb-2">
          <span class="text-xs text-gray-500 uppercase tracking-wider font-semibold">Pitch</span>
          <div class="flex items-center gap-2">
            <span class={"text-xs font-mono font-bold " <>
              cond do
                @deck.pitch_adjust > 0 -> "text-green-400"
                @deck.pitch_adjust < 0 -> "text-red-400"
                true -> "text-gray-500"
              end}>
              {format_pitch(@deck.pitch_adjust)}
            </span>
            <button
              phx-click="pitch_reset"
              phx-target={@myself}
              phx-value-deck={@deck_number}
              disabled={@deck.pitch_adjust == 0.0}
              class={"px-2 py-0.5 text-xs font-bold rounded transition-colors " <>
                if(@deck.pitch_adjust == 0.0,
                  do: "bg-gray-700 text-gray-600 cursor-not-allowed",
                  else: "bg-gray-700 text-gray-300 hover:bg-gray-600"
                )}
            >
              RESET
            </button>
          </div>
        </div>

        <form phx-change="set_pitch" phx-target={@myself} phx-value-deck={@deck_number} class="mb-2">
          <input
            type="range"
            min="-80"
            max="80"
            step="1"
            value={trunc(@deck.pitch_adjust * 10)}
            name="value"
            aria-label={"Pitch adjust deck #{@deck_number}"}
            class={"w-full h-1.5 rounded-lg appearance-none cursor-pointer " <>
              if(@deck_number == 1, do: "accent-cyan-500", else: "accent-orange-500")}
          />
          <div class="flex justify-between mt-0.5">
            <span class="text-xs text-gray-600">-8%</span>
            <span class="text-xs text-gray-600">0</span>
            <span class="text-xs text-gray-600">+8%</span>
          </div>
        </form>

        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1.5">
            <span class="text-xs text-gray-500 uppercase">Adj. BPM</span>
            <span class={"text-sm font-bold font-mono " <>
              if(@deck.tempo_bpm > 0, do: "text-yellow-400", else: "text-gray-600")}>
              {format_adjusted_bpm(@deck.tempo_bpm, @deck.pitch_adjust)}
            </span>
          </div>
          <button
            phx-click="sync_deck"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            disabled={is_nil(@deck.track) || @deck.tempo_bpm <= 0}
            class={"px-3 py-1 text-xs font-bold rounded transition-colors " <>
              if(is_nil(@deck.track) || @deck.tempo_bpm <= 0,
                do: "bg-gray-700 text-gray-600 cursor-not-allowed",
                else: "bg-yellow-600 text-white hover:bg-yellow-500"
              )}
          >
            SYNC
          </button>
        </div>
      </div>

      <%!-- Loop Controls --%>
      <div class="mb-4 border border-gray-700/50 rounded-lg p-3">
        <div class="flex items-center justify-between mb-2">
          <span class="text-xs text-gray-500 uppercase tracking-wider font-semibold">Loop</span>
          <span
            :if={@deck.loop_active}
            class={"text-xs px-2 py-0.5 rounded-full font-bold animate-pulse " <>
              if(@deck_number == 1, do: "bg-cyan-500/20 text-cyan-400", else: "bg-orange-500/20 text-orange-400")}
          >
            LOOP
          </span>
        </div>

        <div class="flex items-center gap-2 mb-2">
          <button
            phx-click="loop_in"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            disabled={is_nil(@deck.track)}
            class={"flex-1 px-3 py-1.5 text-xs font-bold rounded transition-colors " <>
              cond do
                is_nil(@deck.track) -> "bg-gray-700 text-gray-600 cursor-not-allowed"
                @deck.loop_start_ms != nil -> if(@deck_number == 1, do: "bg-cyan-600 text-white", else: "bg-orange-600 text-white")
                true -> "bg-gray-700 text-gray-300 hover:bg-gray-600"
              end}
          >
            IN
          </button>

          <button
            phx-click="loop_out"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            disabled={is_nil(@deck.track) || is_nil(@deck.loop_start_ms)}
            class={"flex-1 px-3 py-1.5 text-xs font-bold rounded transition-colors " <>
              cond do
                is_nil(@deck.track) || is_nil(@deck.loop_start_ms) -> "bg-gray-700 text-gray-600 cursor-not-allowed"
                @deck.loop_end_ms != nil -> if(@deck_number == 1, do: "bg-cyan-600 text-white", else: "bg-orange-600 text-white")
                true -> "bg-gray-700 text-gray-300 hover:bg-gray-600"
              end}
          >
            OUT
          </button>

          <button
            phx-click="loop_toggle"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            disabled={is_nil(@deck.loop_start_ms) || is_nil(@deck.loop_end_ms)}
            aria-label={"Toggle loop deck #{@deck_number}"}
            class={"px-3 py-1.5 text-xs font-bold rounded transition-colors " <>
              cond do
                is_nil(@deck.loop_start_ms) || is_nil(@deck.loop_end_ms) -> "bg-gray-700 text-gray-600 cursor-not-allowed"
                @deck.loop_active -> "bg-green-600 text-white ring-1 ring-green-400/50"
                true -> "bg-gray-700 text-gray-300 hover:bg-gray-600"
              end}
          >
            {if @deck.loop_active, do: "ON", else: "OFF"}
          </button>
        </div>

        <div class="flex items-center gap-1">
          <span class="text-xs text-gray-600 mr-1">Beats:</span>
          <button
            :for={{label, beats} <- [{"1/4", "0.25"}, {"1/2", "0.5"}, {"1", "1"}, {"2", "2"}, {"4", "4"}, {"8", "8"}]}
            phx-click="loop_size"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            phx-value-beats={beats}
            disabled={is_nil(@deck.track) || @deck.tempo_bpm <= 0}
            class={"flex-1 px-1 py-1 text-xs font-mono font-bold rounded text-center transition-colors " <>
              if(is_nil(@deck.track) || @deck.tempo_bpm <= 0,
                do: "bg-gray-700 text-gray-600 cursor-not-allowed",
                else: "bg-gray-700 text-gray-300 hover:bg-purple-600 hover:text-white"
              )}
          >
            {label}
          </button>
        </div>
      </div>

      <%!-- Per-Deck Volume --%>
      <div class="mt-3 border-t border-gray-700/50 pt-3">
        <div class="flex items-center gap-3">
          <label class="text-xs text-gray-500 uppercase tracking-wider whitespace-nowrap">Volume</label>
          <form phx-change="set_deck_volume" phx-target={@myself} phx-value-deck={@deck_number} class="flex-1 flex items-center gap-2">
            <input
              type="range"
              min="0"
              max="100"
              value={@volume}
              name="level"
              aria-label={"Deck #{@deck_number} volume"}
              class={"w-full h-1.5 rounded-lg appearance-none cursor-pointer " <>
                if(@deck_number == 1, do: "accent-cyan-500", else: "accent-orange-500")}
            />
          </form>
          <span class={"text-sm font-mono font-bold w-10 text-right " <>
            if(@deck_number == 1, do: "text-cyan-400", else: "text-orange-400")}>
            {@volume}%
          </span>
        </div>
      </div>

      <%!-- Track Loader --%>
      <div class="mt-3 border-t border-gray-700/50 pt-3">
        <label class="text-xs text-gray-500 uppercase tracking-wider mb-1 block">Load Track</label>
        <form phx-change="load_track" phx-target={@myself} phx-value-deck={@deck_number}>
          <select
            name="track_id"
            aria-label={"Select track for deck #{@deck_number}"}
            class="w-full bg-gray-800 border border-gray-600 rounded-lg px-3 py-2 text-sm text-white focus:border-purple-500 focus:ring-1 focus:ring-purple-500 appearance-none"
          >
            <option value="">-- Select a track --</option>
            <option
              :for={track <- @tracks}
              value={track.id}
              selected={@deck.track && @deck.track.id == track.id}
            >
              {track.title}{if track.artist, do: " - #{track.artist}", else: ""}
            </option>
          </select>
        </form>
      </div>
    </div>
    """
  end

  # -- Private helpers --

  defp upload_error_to_string(:too_large), do: "File is too large (max 5MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not accepted (use .tsi or .touchosc)"
  defp upload_error_to_string(:too_many_files), do: "Only one file at a time"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"

  defp empty_deck_state do
    %{
      track: nil,
      playing: false,
      tempo_bpm: 0.0,
      pitch_adjust: 0.0,
      position: 0,
      stems: [],
      audio_urls: [],
      loop_active: false,
      loop_start_ms: nil,
      loop_end_ms: nil,
      midi_sync: false,
      structure: %{},
      loop_points: [],
      bar_times: [],
      arrangement_markers: [],
      current_section: nil
    }
  end

  defp deck_assign_key(1), do: :deck_1
  defp deck_assign_key(2), do: :deck_2

  defp cue_points_assign_key(1), do: :deck_1_cue_points
  defp cue_points_assign_key(2), do: :deck_2_cue_points

  defp cue_point_colors do
    ["#ef4444", "#f97316", "#eab308", "#22c55e", "#06b6d4", "#3b82f6", "#8b5cf6", "#ec4899"]
  end

  defp encode_cue_points(cue_points) do
    Enum.map(cue_points, fn cp ->
      %{
        id: cp.id,
        position_ms: cp.position_ms,
        label: cp.label,
        color: cp.color,
        cue_type: to_string(cp.cue_type)
      }
    end)
  end

  defp extract_analysis_data(nil), do: {nil, [], %{}, [], [], []}

  defp extract_analysis_data(track) do
    track = SoundForge.Repo.preload(track, :analysis_results)

    case track.analysis_results do
      [result | _] when not is_nil(result) ->
        features = result.features || %{}

        # Beats are stored under "beats" (flat list of seconds) by the Python analyzer
        beat_times = Map.get(features, "beats", [])

        structure = Map.get(features, "structure", %{})
        loop_points = get_in(features, ["loop_points", "recommended"]) || []
        bar_times = get_in(features, ["structure", "bar_times"]) || []
        arrangement_markers = Map.get(features, "arrangement_markers", [])

        {result.tempo, beat_times, structure, loop_points, bar_times, arrangement_markers}

      _ ->
        {nil, [], %{}, [], [], []}
    end
  end

  defp find_section_boundary(segments, current_pos, "forward") do
    Enum.find_value(segments, fn seg ->
      if seg["start_time"] > current_pos + 0.5, do: seg["start_time"]
    end)
  end

  defp find_section_boundary(segments, current_pos, "back") do
    segments
    |> Enum.reverse()
    |> Enum.find_value(fn seg ->
      if seg["start_time"] < current_pos - 0.5, do: seg["start_time"]
    end)
  end

  defp find_section_boundary(_segments, _current_pos, _direction), do: nil

  defp current_section_label(segments, position) when is_list(segments) do
    Enum.find_value(segments, fn seg ->
      start_time = seg["start_time"] || 0
      end_time = seg["end_time"] || 0

      if position >= start_time && position < end_time do
        seg["label"] || seg["section_type"] || "Unknown"
      end
    end)
  end

  defp current_section_label(_segments, _position), do: nil

  defp quantize_to_beat(position_ms, bpm) when is_number(bpm) and bpm > 0 do
    beat_length_ms = 60_000 / bpm
    beat_index = round(position_ms / beat_length_ms)
    trunc(beat_index * beat_length_ms)
  end

  defp quantize_to_beat(position_ms, _bpm), do: position_ms

  defp parse_beats(beats_str) do
    case Float.parse(beats_str) do
      {val, _} -> val
      :error -> 1.0
    end
  end

  defp persist_pitch(user_id, deck_number, pitch) do
    case DJ.get_or_create_deck_session(user_id, deck_number) do
      {:ok, session} -> DJ.update_deck_session(session, %{pitch_adjust: pitch})
      _ -> :ok
    end
  end

  defp persist_loop(user_id, deck_number, loop_start_ms, loop_end_ms) do
    case DJ.get_or_create_deck_session(user_id, deck_number) do
      {:ok, session} ->
        DJ.update_deck_session(session, %{
          loop_start_ms: loop_start_ms,
          loop_end_ms: loop_end_ms
        })

      _ ->
        :ok
    end
  end

  defp build_stem_urls(stems, _track) when is_list(stems) and stems != [] do
    Enum.map(stems, fn stem ->
      relative = make_relative_path(stem.file_path)
      %{type: to_string(stem.stem_type), url: "/files/#{relative}"}
    end)
  end

  defp build_stem_urls([], track) when not is_nil(track) do
    case Music.get_download_path(track.id) do
      {:ok, path} when is_binary(path) ->
        relative = make_relative_path(path)
        [%{type: "full_track", url: "/files/#{relative}"}]

      _ ->
        []
    end
  end

  defp build_stem_urls(_, _), do: []

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

  defp format_position(seconds) when is_number(seconds) do
    minutes = trunc(seconds / 60)
    secs = trunc(rem(trunc(seconds), 60))

    "#{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(secs), 2, "0")}"
  end

  defp format_position(_), do: "00:00"

  defp format_bpm(bpm) when is_float(bpm) and bpm > 0,
    do: :erlang.float_to_binary(bpm, decimals: 1)

  defp format_bpm(bpm) when is_integer(bpm) and bpm > 0, do: "#{bpm}.0"
  defp format_bpm(_), do: "---"

  defp format_pitch(pitch) when is_number(pitch) do
    sign = if pitch >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(pitch / 1, decimals: 1)}%"
  end

  defp format_pitch(_), do: "+0.0%"

  defp format_adjusted_bpm(bpm, pitch) when is_number(bpm) and bpm > 0 and is_number(pitch) do
    adjusted = bpm * (1.0 + pitch / 100.0)
    :erlang.float_to_binary(adjusted / 1, decimals: 1)
  end

  defp format_adjusted_bpm(_, _), do: "---"

  defp list_user_tracks(scope) when is_map(scope) and not is_nil(scope) do
    Music.list_tracks(scope, sort_by: :title)
  rescue
    _ -> []
  end

  defp list_user_tracks(_) do
    Music.list_tracks(sort_by: :title)
  rescue
    _ -> []
  end
end
