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
  alias SoundForge.DJ.{Chef, Presets, Timecode}
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
     |> assign(:deck_1_stem_loops, [])
     |> assign(:deck_2_stem_loops, [])
     |> assign(:deck_1_stem_loops_open, false)
     |> assign(:deck_2_stem_loops_open, false)
     |> assign(:detecting_cues_deck_1, false)
     |> assign(:detecting_cues_deck_2, false)
     |> assign(:preset_section_open, false)
     |> assign(:chef_panel_open, false)
     |> assign(:chef_prompt, "")
     |> assign(:chef_cooking, false)
     |> assign(:chef_progress_message, nil)
     |> assign(:chef_recipe, nil)
     |> assign(:chef_error, nil)
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

  def update(%{auto_cues_complete: %{track_id: track_id}}, socket) do
    user_id = socket.assigns[:current_user_id]

    socket =
      Enum.reduce([{:deck_1, 1}, {:deck_2, 2}], socket, fn {deck_key, deck_number}, acc ->
        deck = Map.get(acc.assigns, deck_key)

        if deck.track && deck.track.id == track_id do
          cue_points_key = cue_points_assign_key(deck_number)
          detecting_key = detecting_cues_key(deck_number)

          cue_points =
            if user_id, do: DJ.list_cue_points(track_id, user_id), else: []

          acc
          |> assign(cue_points_key, cue_points)
          |> assign(detecting_key, false)
          |> push_event("set_cue_points", %{
            deck: deck_number,
            cue_points: encode_cue_points(cue_points)
          })
        else
          acc
        end
      end)

    {:ok, socket}
  end

  def update(%{chef_progress: payload}, socket) do
    {:ok,
     socket
     |> assign(:chef_cooking, true)
     |> assign(:chef_progress_message, payload[:message] || payload["message"])}
  end

  def update(%{chef_complete: payload}, socket) do
    {:ok,
     socket
     |> assign(:chef_cooking, false)
     |> assign(:chef_progress_message, nil)
     |> assign(:chef_recipe, payload)}
  end

  def update(%{chef_failed: payload}, socket) do
    reason = payload[:reason] || payload["reason"] || "Unknown error"

    {:ok,
     socket
     |> assign(:chef_cooking, false)
     |> assign(:chef_progress_message, nil)
     |> assign(:chef_error, reason)}
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
          stem_loops_key = stem_loops_assign_key(deck_number)
          detecting_key = detecting_cues_key(deck_number)

          cue_points =
            if user_id && track do
              DJ.list_cue_points(track.id, user_id)
            else
              []
            end

          stem_loops =
            if user_id && track do
              DJ.list_stem_loops(track.id, user_id)
            else
              []
            end

          # Subscribe to PubSub for auto-cue completion broadcasts
          if track do
            SoundForgeWeb.Endpoint.subscribe("tracks:#{track.id}")
          end

          socket =
            socket
            |> assign(deck_key, deck_state)
            |> assign(cue_points_key, cue_points)
            |> assign(stem_loops_key, stem_loops)
            |> assign(detecting_key, false)
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

  # -- Auto Cue Controls --

  @impl true
  def handle_event("auto_detect_cues", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    user_id = socket.assigns[:current_user_id]
    detecting_key = detecting_cues_key(deck_number)

    if deck.track && user_id do
      case DJ.generate_auto_cues(deck.track.id, user_id) do
        {:ok, _job} ->
          # Subscribe to the track's PubSub topic for completion broadcast
          SoundForgeWeb.Endpoint.subscribe("tracks:#{deck.track.id}")

          {:noreply, assign(socket, detecting_key, true)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start auto-cue detection")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("promote_auto_cue", %{"deck" => deck_str, "cue_id" => cue_id}, socket) do
    deck_number = String.to_integer(deck_str)
    cue_points_key = cue_points_assign_key(deck_number)

    case DJ.get_cue_point(cue_id) do
      %DJ.CuePoint{auto_generated: true} = cue_point ->
        case DJ.update_cue_point(cue_point, %{auto_generated: false}) do
          {:ok, updated_cue} ->
            existing_cues = Map.get(socket.assigns, cue_points_key)

            updated_cues =
              Enum.map(existing_cues, fn cp ->
                if cp.id == updated_cue.id, do: updated_cue, else: cp
              end)

            socket =
              socket
              |> assign(cue_points_key, updated_cues)
              |> push_event("set_cue_points", %{
                deck: deck_number,
                cue_points: encode_cue_points(updated_cues)
              })

            {:noreply, socket}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to promote cue point")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dismiss_auto_cue", %{"deck" => deck_str, "cue_id" => cue_id}, socket) do
    deck_number = String.to_integer(deck_str)
    cue_points_key = cue_points_assign_key(deck_number)
    existing_cues = Map.get(socket.assigns, cue_points_key)

    case DJ.get_cue_point(cue_id) do
      %DJ.CuePoint{auto_generated: true} = cue_point ->
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
            {:noreply, put_flash(socket, :error, "Failed to dismiss auto cue")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("regenerate_auto_cues", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    user_id = socket.assigns[:current_user_id]
    detecting_key = detecting_cues_key(deck_number)
    cue_points_key = cue_points_assign_key(deck_number)

    if deck.track && user_id do
      # Delete existing auto cues first (worker also does this, but clear UI immediately)
      DJ.delete_auto_cue_points(deck.track.id, user_id)

      # Refresh cue points list (keeps manual cues, removes auto ones)
      cue_points = DJ.list_cue_points(deck.track.id, user_id)

      case DJ.generate_auto_cues(deck.track.id, user_id) do
        {:ok, _job} ->
          SoundForgeWeb.Endpoint.subscribe("tracks:#{deck.track.id}")

          socket =
            socket
            |> assign(detecting_key, true)
            |> assign(cue_points_key, cue_points)
            |> push_event("set_cue_points", %{
              deck: deck_number,
              cue_points: encode_cue_points(cue_points)
            })

          {:noreply, socket}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(cue_points_key, cue_points)
           |> put_flash(:error, "Failed to regenerate auto cues")}
      end
    else
      {:noreply, socket}
    end
  end

  # -- Chef Controls --

  @impl true
  def handle_event("toggle_chef_panel", _params, socket) do
    {:noreply, assign(socket, :chef_panel_open, !socket.assigns.chef_panel_open)}
  end

  @impl true
  def handle_event("chef_prompt_change", %{"prompt" => prompt}, socket) do
    {:noreply, assign(socket, :chef_prompt, prompt)}
  end

  @impl true
  def handle_event("chef_cook", _params, socket) do
    prompt = String.trim(socket.assigns.chef_prompt)
    user_id = socket.assigns[:current_user_id]

    if prompt == "" or is_nil(user_id) do
      {:noreply, socket}
    else
      socket =
        socket
        |> assign(:chef_cooking, true)
        |> assign(:chef_error, nil)
        |> assign(:chef_recipe, nil)
        |> assign(:chef_progress_message, "Parsing your request...")

      # Enqueue the ChefWorker for async processing with PubSub progress
      case Chef.cook(prompt, user_id) do
        {:ok, recipe} ->
          {:noreply,
           socket
           |> assign(:chef_cooking, false)
           |> assign(:chef_progress_message, nil)
           |> assign(:chef_recipe, recipe_to_map(recipe))}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:chef_cooking, false)
           |> assign(:chef_progress_message, nil)
           |> assign(:chef_error, humanize_chef_error(reason))}
      end
    end
  end

  @impl true
  def handle_event("chef_load_recipe", _params, socket) do
    recipe = socket.assigns.chef_recipe

    if recipe do
      deck_assignments = recipe[:deck_assignments] || recipe["deck_assignments"] || []

      # Load the first track assigned to each deck
      socket =
        Enum.reduce(deck_assignments, socket, fn assignment, acc ->
          deck = assignment[:deck] || assignment["deck"]
          track_id = assignment[:track_id] || assignment["track_id"]
          order = assignment[:order] || assignment["order"] || 0

          # Only load the first track per deck (order 0 for deck 1, order 1 for deck 2)
          if (deck == 1 and order == 0) or (deck == 2 and order == 1) do
            user_id = acc.assigns[:current_user_id]

            case DJ.load_track_to_deck(user_id, deck, track_id) do
              {:ok, session} ->
                track = session.track
                stems = if track, do: track.stems || [], else: []
                audio_urls = build_stem_urls(stems, track)
                pitch = session.pitch_adjust || 0.0

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

                deck_key = deck_assign_key(deck)
                cue_points_key = cue_points_assign_key(deck)

                cue_points =
                  if user_id && track, do: DJ.list_cue_points(track.id, user_id), else: []

                if track, do: SoundForgeWeb.Endpoint.subscribe("tracks:#{track.id}")

                acc
                |> assign(deck_key, deck_state)
                |> assign(cue_points_key, cue_points)
                |> push_event("load_deck_audio", %{
                  deck: deck,
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
                  deck: deck,
                  cue_points: encode_cue_points(cue_points)
                })
                |> push_event("set_pitch", %{deck: deck, value: pitch})

              {:error, _} ->
                acc
            end
          else
            acc
          end
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("chef_load_to_pads", _params, socket) do
    recipe = socket.assigns.chef_recipe
    user_id = socket.assigns[:current_user_id]

    if recipe && user_id do
      alias SoundForge.Sampler

      # Collect all track_ids from the recipe
      track_ids =
        (recipe[:tracks] || recipe["tracks"] || [])
        |> Enum.map(fn t -> t[:track_id] || t["track_id"] end)
        |> Enum.reject(&is_nil/1)

      # Gather stems from all recipe tracks
      stems =
        track_ids
        |> Enum.flat_map(fn track_id ->
          Music.list_stems_for_track(track_id)
        end)
        |> Enum.take(16)

      if stems != [] do
        prompt = recipe[:prompt] || recipe["prompt"] || "Chef Recipe"
        bank_name = "Chef: " <> String.slice(prompt, 0, 30)
        position = length(Sampler.list_banks(user_id))

        case Sampler.create_bank(%{name: bank_name, user_id: user_id, position: position}) do
          {:ok, bank} ->
            case Sampler.quick_load_stems(bank, stems) do
              {:ok, _bank} ->
                {:noreply, put_flash(socket, :info, "Recipe loaded to Pads bank '#{bank_name}'")}

              _ ->
                {:noreply, put_flash(socket, :error, "Failed to load stems to pads")}
            end

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create pad bank")}
        end
      else
        {:noreply, put_flash(socket, :error, "No stems found for recipe tracks. Run stem separation first.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("chef_remix", _params, socket) do
    {:noreply,
     socket
     |> assign(:chef_recipe, nil)
     |> assign(:chef_error, nil)
     |> assign(:chef_cooking, false)
     |> assign(:chef_progress_message, nil)}
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

  # -- Stem Loop Controls --

  @impl true
  def handle_event("toggle_stem_loops", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    open_key = stem_loops_open_key(deck_number)
    {:noreply, assign(socket, open_key, !Map.get(socket.assigns, open_key))}
  end

  @impl true
  def handle_event(
        "set_stem_loop_as_deck_loop",
        %{"deck" => deck_str, "loop_id" => loop_id},
        socket
      ) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    case DJ.get_stem_loop(loop_id) do
      %DJ.StemLoop{} = stem_loop when not is_nil(deck.track) ->
        updated_deck = %{
          deck
          | loop_start_ms: stem_loop.start_ms,
            loop_end_ms: stem_loop.end_ms,
            loop_active: true
        }

        user_id = socket.assigns[:current_user_id]
        persist_loop(user_id, deck_number, stem_loop.start_ms, stem_loop.end_ms)

        socket =
          socket
          |> assign(deck_key, updated_deck)
          |> push_event("set_loop", %{
            deck: deck_number,
            loop_start_ms: stem_loop.start_ms,
            loop_end_ms: stem_loop.end_ms,
            active: true
          })

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "create_stem_loop",
        %{"deck" => deck_str, "stem_id" => stem_id, "start_ms" => start_str, "end_ms" => end_str},
        socket
      ) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    user_id = socket.assigns[:current_user_id]
    stem_loops_key = stem_loops_assign_key(deck_number)

    if deck.track && user_id do
      start_ms = parse_integer(start_str)
      end_ms = parse_integer(end_str)

      stem = Enum.find(deck.stems, &(to_string(&1.id) == stem_id))
      color = if stem, do: stem_type_color(stem.stem_type), else: "#96CEB4"

      attrs = %{
        stem_id: stem_id,
        track_id: deck.track.id,
        user_id: user_id,
        start_ms: start_ms,
        end_ms: end_ms,
        label: "Loop #{length(Map.get(socket.assigns, stem_loops_key, [])) + 1}",
        color: color
      }

      case DJ.create_stem_loop(attrs) do
        {:ok, _stem_loop} ->
          updated_loops = DJ.list_stem_loops(deck.track.id, user_id)
          {:noreply, assign(socket, stem_loops_key, updated_loops)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to create stem loop")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_stem_loop", %{"deck" => deck_str, "loop_id" => loop_id}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    user_id = socket.assigns[:current_user_id]
    stem_loops_key = stem_loops_assign_key(deck_number)

    case DJ.get_stem_loop(loop_id) do
      %DJ.StemLoop{} = stem_loop ->
        case DJ.delete_stem_loop(stem_loop) do
          {:ok, _} ->
            updated_loops =
              if deck.track && user_id do
                DJ.list_stem_loops(deck.track.id, user_id)
              else
                []
              end

            {:noreply, assign(socket, stem_loops_key, updated_loops)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete stem loop")}
        end

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "audition_stem_loop",
        %{"deck" => deck_str, "loop_id" => loop_id},
        socket
      ) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    case DJ.get_stem_loop(loop_id) do
      %DJ.StemLoop{} = stem_loop when not is_nil(deck.track) ->
        stem_loop = SoundForge.Repo.preload(stem_loop, :stem)

        stem_url =
          if stem_loop.stem && stem_loop.stem.file_path do
            relative = make_relative_path(stem_loop.stem.file_path)
            "/files/#{relative}"
          else
            nil
          end

        if stem_url do
          socket =
            push_event(socket, "stem_loop_preview", %{
              deck: deck_number,
              stem_type: to_string(stem_loop.stem.stem_type),
              url: stem_url,
              start_ms: stem_loop.start_ms,
              end_ms: stem_loop.end_ms
            })

          {:noreply, socket}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  # -- Send to Pad: assigns stem to the next empty pad in the user's current bank --

  @impl true
  def handle_event("send_to_pad", %{"stem_id" => stem_id}, socket) do
    user_id = socket.assigns[:current_user_id]

    if user_id do
      alias SoundForge.Sampler

      banks = Sampler.list_banks(user_id)
      bank = List.first(banks)

      if bank do
        empty_pad =
          bank.pads
          |> Enum.sort_by(& &1.index)
          |> Enum.find(fn pad -> is_nil(pad.stem_id) end)

        if empty_pad do
          case Sampler.assign_stem_to_pad(empty_pad, stem_id) do
            {:ok, updated_pad} ->
              stem = updated_pad.stem
              label = if stem, do: stem.stem_type |> to_string() |> String.capitalize(), else: nil
              color = if stem, do: Sampler.stem_type_color(stem.stem_type), else: "#6b7280"
              Sampler.update_pad(updated_pad, %{label: label, color: color})

              {:noreply, put_flash(socket, :info, "Stem sent to #{bank.name}, Pad #{empty_pad.index + 1}")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to assign stem to pad")}
          end
        else
          {:noreply, put_flash(socket, :error, "No empty pads in #{bank.name}. Create a new bank.")}
        end
      else
        {:noreply, put_flash(socket, :error, "No pad banks found. Switch to Pads view first.")}
      end
    else
      {:noreply, socket}
    end
  end

  # -- Load to Pads: assigns Chef recipe stems to a new or existing bank --

  @impl true
  def handle_event("load_to_pads", %{"recipe_name" => recipe_name} = params, socket) do
    user_id = socket.assigns[:current_user_id]
    stem_ids = Map.get(params, "stem_ids", [])

    if user_id && stem_ids != [] do
      alias SoundForge.Sampler

      bank_name = recipe_name || "Chef Recipe"
      position = length(Sampler.list_banks(user_id))

      case Sampler.create_bank(%{name: bank_name, user_id: user_id, position: position}) do
        {:ok, bank} ->
          stems =
            stem_ids
            |> Enum.map(fn id ->
              try do
                SoundForge.Repo.get(SoundForge.Music.Stem, id)
              rescue
                _ -> nil
              end
            end)
            |> Enum.reject(&is_nil/1)
            |> Enum.take(16)

          case Sampler.quick_load_stems(bank, stems) do
            {:ok, _bank} ->
              {:noreply, put_flash(socket, :info, "Recipe loaded to Pads bank '#{bank_name}'")}

            _ ->
              {:noreply, put_flash(socket, :error, "Failed to load stems to pads")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to create pad bank")}
      end
    else
      {:noreply, put_flash(socket, :error, "No stems to load")}
    end
  end

  def handle_event("load_to_pads", _params, socket) do
    {:noreply, put_flash(socket, :error, "No recipe name provided")}
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
            detecting_cues={@detecting_cues_deck_1}
            midi_sync={@deck_1.midi_sync}
            structure={@deck_1.structure || %{}}
            loop_points={@deck_1.loop_points || []}
            bar_times={@deck_1.bar_times || []}
            arrangement_markers={@deck_1.arrangement_markers || []}
            stem_loops={@deck_1_stem_loops}
            stem_loops_open={@deck_1_stem_loops_open}
            myself={@myself}
          />

          <%!-- DECK 2 --%>
          <.deck_panel
            deck_number={2}
            deck={@deck_2}
            tracks={@tracks}
            volume={@deck_2_volume}
            cue_points={@deck_2_cue_points}
            detecting_cues={@detecting_cues_deck_2}
            midi_sync={@deck_2.midi_sync}
            structure={@deck_2.structure || %{}}
            loop_points={@deck_2.loop_points || []}
            bar_times={@deck_2.bar_times || []}
            arrangement_markers={@deck_2.arrangement_markers || []}
            stem_loops={@deck_2_stem_loops}
            stem_loops_open={@deck_2_stem_loops_open}
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

        <%!-- Chef AI Panel --%>
        <div class="mt-4 bg-gradient-to-r from-amber-950/30 to-orange-950/30 rounded-xl border border-amber-700/30">
          <button
            phx-click="toggle_chef_panel"
            phx-target={@myself}
            class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-amber-300 hover:text-amber-200 transition-colors"
          >
            <span class="flex items-center gap-2">
              <svg class="w-5 h-5 text-orange-400" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z" opacity="0" />
                <path d="M12.75 2.25c-.41 0-.75.34-.75.75v1.5c0 .41.34.75.75.75s.75-.34.75-.75V3c0-.41-.34-.75-.75-.75zM7.5 4.57a.75.75 0 00-1.06 0L5.38 5.63a.75.75 0 001.06 1.06l1.06-1.06a.75.75 0 000-1.06zM18 4.57a.75.75 0 00-1.06 0l-1.06 1.06a.75.75 0 001.06 1.06l1.06-1.06a.75.75 0 000-1.06z" opacity="0.5" />
                <path d="M12 6c-3.31 0-6 2.69-6 6 0 1.85.84 3.51 2.16 4.61.28.23.34.64.34 1V19c0 .55.45 1 1 1h5c.55 0 1-.45 1-1v-1.39c0-.36.06-.77.34-1A5.99 5.99 0 0018 12c0-3.31-2.69-6-6-6zm1.5 14h-3v-1h3v1zm0-2h-3v-1h3v1z" />
              </svg>
              <span class="font-bold tracking-wide">Chef AI</span>
              <span class="text-xs text-amber-500/70 font-normal">AI-Powered Set Builder</span>
            </span>
            <svg
              class={"w-4 h-4 transition-transform " <> if(@chef_panel_open, do: "rotate-180", else: "")}
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
            </svg>
          </button>

          <div :if={@chef_panel_open} class="px-4 pb-4 border-t border-amber-700/30">
            <%!-- Prompt Input (shown when no recipe) --%>
            <div :if={is_nil(@chef_recipe)} class="mt-3">
              <form phx-submit="chef_cook" phx-target={@myself}>
                <div class="flex flex-col gap-3">
                  <textarea
                    name="prompt"
                    value={@chef_prompt}
                    phx-change="chef_prompt_change"
                    phx-target={@myself}
                    placeholder="Describe your ideal mix... e.g. 'Deep house set, 120-125 BPM, build energy from chill to peak'"
                    rows="3"
                    disabled={@chef_cooking}
                    class="w-full px-4 py-3 bg-gray-900/80 border border-amber-700/40 rounded-lg text-gray-200 placeholder-gray-500 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500/50 focus:border-amber-500/50 resize-none disabled:opacity-50"
                  />
                  <div class="flex items-center justify-between">
                    <p class="text-xs text-amber-600/60">
                      Chef will search your library and build a compatible set.
                    </p>
                    <button
                      type="submit"
                      disabled={@chef_cooking || String.trim(@chef_prompt) == ""}
                      class={"flex items-center gap-2 px-5 py-2.5 text-sm font-bold rounded-lg transition-all " <>
                        if(@chef_cooking || String.trim(@chef_prompt) == "",
                          do: "bg-gray-700 text-gray-500 cursor-not-allowed",
                          else: "bg-gradient-to-r from-amber-600 to-orange-600 text-white hover:from-amber-500 hover:to-orange-500 shadow-lg shadow-amber-900/30"
                        )}
                    >
                      <%!-- Flame Icon --%>
                      <svg class="w-4 h-4" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M13.5.67s.74 2.65.74 4.8c0 2.06-1.35 3.73-3.41 3.73-2.07 0-3.63-1.67-3.63-3.73l.03-.36C5.21 7.51 4 10.62 4 14c0 4.42 3.58 8 8 8s8-3.58 8-8C20 8.61 17.41 3.8 13.5.67zM11.71 19c-1.78 0-3.22-1.4-3.22-3.14 0-1.62 1.05-2.76 2.81-3.12 1.77-.36 3.6-1.21 4.62-2.58.39 1.29.59 2.65.59 4.04 0 2.65-2.15 4.8-4.8 4.8z" />
                      </svg>
                      {if @chef_cooking, do: "Cooking...", else: "Let me cook"}
                    </button>
                  </div>
                </div>
              </form>

              <%!-- Loading State --%>
              <div :if={@chef_cooking} class="mt-4 flex items-center gap-3 p-3 bg-amber-900/20 rounded-lg border border-amber-700/30">
                <div class="chef-flame-animation flex-shrink-0">
                  <svg class="w-6 h-6 text-orange-400 animate-pulse" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M13.5.67s.74 2.65.74 4.8c0 2.06-1.35 3.73-3.41 3.73-2.07 0-3.63-1.67-3.63-3.73l.03-.36C5.21 7.51 4 10.62 4 14c0 4.42 3.58 8 8 8s8-3.58 8-8C20 8.61 17.41 3.8 13.5.67zM11.71 19c-1.78 0-3.22-1.4-3.22-3.14 0-1.62 1.05-2.76 2.81-3.12 1.77-.36 3.6-1.21 4.62-2.58.39 1.29.59 2.65.59 4.04 0 2.65-2.15 4.8-4.8 4.8z" />
                  </svg>
                </div>
                <div class="flex-1">
                  <p class="text-sm text-amber-300 font-medium">Chef is cooking...</p>
                  <p :if={@chef_progress_message} class="text-xs text-amber-500/80 mt-0.5">
                    {@chef_progress_message}
                  </p>
                </div>
                <div class="flex gap-1">
                  <span class="w-1.5 h-1.5 bg-orange-400 rounded-full animate-bounce" style="animation-delay: 0ms"></span>
                  <span class="w-1.5 h-1.5 bg-orange-400 rounded-full animate-bounce" style="animation-delay: 150ms"></span>
                  <span class="w-1.5 h-1.5 bg-orange-400 rounded-full animate-bounce" style="animation-delay: 300ms"></span>
                </div>
              </div>

              <%!-- Error State --%>
              <div :if={@chef_error} class="mt-4 p-3 bg-red-900/20 rounded-lg border border-red-700/30">
                <div class="flex items-start gap-2">
                  <svg class="w-4 h-4 text-red-400 mt-0.5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                  </svg>
                  <p class="text-sm text-red-300">{@chef_error}</p>
                </div>
              </div>
            </div>

            <%!-- Recipe Card (shown when recipe exists) --%>
            <div :if={@chef_recipe} class="mt-3">
              <.chef_recipe_card recipe={@chef_recipe} myself={@myself} />
            </div>
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

  # -- Chef Recipe Sub-Component --

  attr :recipe, :map, required: true
  attr :myself, :any, required: true

  defp chef_recipe_card(assigns) do
    tracks = assigns.recipe[:tracks] || assigns.recipe["tracks"] || []
    deck_assignments = assigns.recipe[:deck_assignments] || assigns.recipe["deck_assignments"] || []
    mixing_notes = assigns.recipe[:mixing_notes] || assigns.recipe["mixing_notes"] || ""
    stems_to_load = assigns.recipe[:stems_to_load] || assigns.recipe["stems_to_load"] || []
    prompt = assigns.recipe[:prompt] || assigns.recipe["prompt"] || ""

    deck_1_tracks =
      deck_assignments
      |> Enum.filter(fn a -> (a[:deck] || a["deck"]) == 1 end)
      |> Enum.sort_by(fn a -> a[:order] || a["order"] || 0 end)

    deck_2_tracks =
      deck_assignments
      |> Enum.filter(fn a -> (a[:deck] || a["deck"]) == 2 end)
      |> Enum.sort_by(fn a -> a[:order] || a["order"] || 0 end)

    assigns =
      assigns
      |> assign(:tracks, tracks)
      |> assign(:deck_1_tracks, deck_1_tracks)
      |> assign(:deck_2_tracks, deck_2_tracks)
      |> assign(:mixing_notes, mixing_notes)
      |> assign(:stems_to_load, stems_to_load)
      |> assign(:prompt, prompt)

    ~H"""
    <div class="space-y-3">
      <%!-- Recipe Header --%>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <svg class="w-5 h-5 text-orange-400" viewBox="0 0 24 24" fill="currentColor">
            <path d="M13.5.67s.74 2.65.74 4.8c0 2.06-1.35 3.73-3.41 3.73-2.07 0-3.63-1.67-3.63-3.73l.03-.36C5.21 7.51 4 10.62 4 14c0 4.42 3.58 8 8 8s8-3.58 8-8C20 8.61 17.41 3.8 13.5.67zM11.71 19c-1.78 0-3.22-1.4-3.22-3.14 0-1.62 1.05-2.76 2.81-3.12 1.77-.36 3.6-1.21 4.62-2.58.39 1.29.59 2.65.59 4.04 0 2.65-2.15 4.8-4.8 4.8z" />
          </svg>
          <h3 class="text-sm font-bold text-amber-300 uppercase tracking-wider">Recipe Ready</h3>
        </div>
        <span class="text-xs text-amber-600/60">{length(@tracks)} tracks</span>
      </div>

      <%!-- Prompt Echo --%>
      <div class="text-xs text-gray-500 italic truncate" title={@prompt}>
        &quot;{@prompt}&quot;
      </div>

      <%!-- Deck Assignments --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <%!-- Deck 1 Tracks --%>
        <div class="bg-gray-900/60 rounded-lg p-3 border border-cyan-700/20">
          <h4 class="text-xs font-bold text-cyan-400 uppercase tracking-wider mb-2">Deck 1</h4>
          <div class="space-y-2">
            <div
              :for={assignment <- @deck_1_tracks}
              class="flex items-center gap-2 p-2 bg-gray-800/50 rounded-md"
            >
              <div class="w-8 h-8 bg-gray-700 rounded flex items-center justify-center flex-shrink-0">
                <svg class="w-4 h-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3" />
                </svg>
              </div>
              <div class="flex-1 min-w-0">
                <% track = find_recipe_track(@tracks, assignment[:track_id] || assignment["track_id"]) %>
                <p class="text-sm text-white font-medium truncate">
                  {if track, do: track[:title] || track["title"], else: "Unknown"}
                </p>
                <p class="text-xs text-gray-400 truncate">
                  {if track, do: track[:artist] || track["artist"], else: ""}
                </p>
              </div>
              <div :if={track} class="flex items-center gap-2 flex-shrink-0">
                <span :if={track[:tempo] || track["tempo"]} class="text-[10px] text-cyan-400 font-mono">
                  {format_recipe_tempo(track[:tempo] || track["tempo"])} BPM
                </span>
                <span :if={track[:key] || track["key"]} class="text-[10px] text-purple-400 font-mono">
                  {track[:key] || track["key"]}
                </span>
                <.compatibility_badge score={track[:compatibility_score] || track["compatibility_score"]} />
              </div>
            </div>
            <p :if={@deck_1_tracks == []} class="text-xs text-gray-600 text-center py-2">No tracks assigned</p>
          </div>
        </div>

        <%!-- Deck 2 Tracks --%>
        <div class="bg-gray-900/60 rounded-lg p-3 border border-orange-700/20">
          <h4 class="text-xs font-bold text-orange-400 uppercase tracking-wider mb-2">Deck 2</h4>
          <div class="space-y-2">
            <div
              :for={assignment <- @deck_2_tracks}
              class="flex items-center gap-2 p-2 bg-gray-800/50 rounded-md"
            >
              <div class="w-8 h-8 bg-gray-700 rounded flex items-center justify-center flex-shrink-0">
                <svg class="w-4 h-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3" />
                </svg>
              </div>
              <div class="flex-1 min-w-0">
                <% track = find_recipe_track(@tracks, assignment[:track_id] || assignment["track_id"]) %>
                <p class="text-sm text-white font-medium truncate">
                  {if track, do: track[:title] || track["title"], else: "Unknown"}
                </p>
                <p class="text-xs text-gray-400 truncate">
                  {if track, do: track[:artist] || track["artist"], else: ""}
                </p>
              </div>
              <div :if={track} class="flex items-center gap-2 flex-shrink-0">
                <span :if={track[:tempo] || track["tempo"]} class="text-[10px] text-orange-400 font-mono">
                  {format_recipe_tempo(track[:tempo] || track["tempo"])} BPM
                </span>
                <span :if={track[:key] || track["key"]} class="text-[10px] text-purple-400 font-mono">
                  {track[:key] || track["key"]}
                </span>
                <.compatibility_badge score={track[:compatibility_score] || track["compatibility_score"]} />
              </div>
            </div>
            <p :if={@deck_2_tracks == []} class="text-xs text-gray-600 text-center py-2">No tracks assigned</p>
          </div>
        </div>
      </div>

      <%!-- Mixing Notes --%>
      <div :if={@mixing_notes != ""} class="p-3 bg-amber-900/15 rounded-lg border border-amber-700/20">
        <div class="flex items-start gap-2">
          <svg class="w-4 h-4 text-amber-400 mt-0.5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div class="text-xs text-amber-200/80 whitespace-pre-line">{@mixing_notes}</div>
        </div>
      </div>

      <%!-- Action Buttons --%>
      <div class="flex items-center gap-3 pt-2">
        <button
          phx-click="chef_load_recipe"
          phx-target={@myself}
          class="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 bg-gradient-to-r from-amber-600 to-orange-600 text-white text-sm font-bold rounded-lg hover:from-amber-500 hover:to-orange-500 transition-all shadow-lg shadow-amber-900/30"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
          </svg>
          Load Recipe
        </button>
        <button
          phx-click="chef_load_to_pads"
          phx-target={@myself}
          class="flex items-center gap-2 px-4 py-2.5 bg-gray-700 text-cyan-300 text-sm font-medium rounded-lg hover:bg-cyan-700 hover:text-white transition-colors border border-cyan-700/30"
          title="Create a Pads bank with this recipe's stems"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M4 5a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 15a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H5a1 1 0 01-1-1v-4zM14 15a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z" />
          </svg>
          Load to Pads
        </button>
        <button
          phx-click="chef_remix"
          phx-target={@myself}
          class="flex items-center gap-2 px-4 py-2.5 bg-gray-700 text-amber-300 text-sm font-medium rounded-lg hover:bg-gray-600 transition-colors border border-amber-700/30"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          Remix
        </button>
      </div>
    </div>
    """
  end

  attr :score, :any, default: nil

  defp compatibility_badge(assigns) do
    score = assigns.score

    {bg, text_color} =
      cond do
        is_nil(score) -> {"bg-gray-700", "text-gray-500"}
        score >= 0.8 -> {"bg-green-900/40", "text-green-400"}
        score >= 0.5 -> {"bg-yellow-900/40", "text-yellow-400"}
        true -> {"bg-red-900/40", "text-red-400"}
      end

    assigns = assign(assigns, bg: bg, text_color: text_color)

    ~H"""
    <span :if={@score} class={"text-[10px] font-bold px-1.5 py-0.5 rounded #{@bg} #{@text_color}"}>
      {trunc((@score || 0) * 100)}%
    </span>
    """
  end

  # -- Sub-Components --

  attr :deck_number, :integer, required: true
  attr :deck, :map, required: true
  attr :tracks, :list, required: true
  attr :volume, :integer, required: true
  attr :cue_points, :list, required: true
  attr :detecting_cues, :boolean, default: false
  attr :midi_sync, :boolean, default: false
  attr :structure, :map, default: %{}
  attr :loop_points, :list, default: []
  attr :bar_times, :list, default: []
  attr :arrangement_markers, :list, default: []
  attr :stem_loops, :list, default: []
  attr :stem_loops_open, :boolean, default: false
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
          <div class="flex items-center gap-2">
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
        </div>
        <%!-- Manual cue pads (non-auto-generated only) --%>
        <% manual_cues = Enum.reject(@cue_points, & &1.auto_generated) %>
        <div class="grid grid-cols-8 gap-1">
          <%= for slot <- 1..8 do %>
            <% cue = Enum.at(manual_cues, slot - 1) %>
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

        <%!-- Auto-Generated Cues Section --%>
        <% auto_cues = Enum.filter(@cue_points, & &1.auto_generated) %>
        <div class="mt-3 pt-3 border-t border-gray-700/30">
          <div class="flex items-center justify-between mb-2">
            <span class="flex items-center gap-1.5 text-xs text-gray-500 uppercase tracking-wider font-semibold">
              <%!-- Sparkle icon for AI indicator --%>
              <svg class="w-3.5 h-3.5 text-amber-400" fill="currentColor" viewBox="0 0 24 24">
                <path d="M12 2L9.19 8.63 2 9.24l5.46 4.73L5.82 21 12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2z" />
              </svg>
              Auto Cues
            </span>
            <div class="flex items-center gap-1.5">
              <%= if @detecting_cues do %>
                <%!-- Loading spinner while AutoCueWorker is processing --%>
                <span class="flex items-center gap-1.5 text-xs text-amber-400">
                  <svg class="w-3.5 h-3.5 animate-spin" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Detecting...
                </span>
              <% else %>
                <%= if length(auto_cues) > 0 do %>
                  <button
                    phx-click="regenerate_auto_cues"
                    phx-target={@myself}
                    phx-value-deck={@deck_number}
                    class="px-2 py-0.5 text-[10px] font-bold rounded bg-gray-700 text-gray-400 hover:bg-amber-600 hover:text-white transition-colors"
                    title="Regenerate all auto cues"
                  >
                    REGEN
                  </button>
                <% else %>
                  <button
                    :if={@deck.track && !@detecting_cues}
                    phx-click="auto_detect_cues"
                    phx-target={@myself}
                    phx-value-deck={@deck_number}
                    class={"px-3 py-1 text-xs font-bold rounded transition-colors " <>
                      if(is_nil(@deck.track),
                        do: "bg-gray-700 text-gray-600 cursor-not-allowed",
                        else: "bg-amber-600 text-white hover:bg-amber-500 ring-1 ring-amber-400/30"
                      )}
                  >
                    AUTO-DETECT
                  </button>
                <% end %>
              <% end %>
            </div>
          </div>

          <%!-- Auto-generated cue list --%>
          <%= if length(auto_cues) > 0 do %>
            <div class="space-y-1">
              <%= for cue <- auto_cues do %>
                <% opacity = confidence_to_opacity(cue.confidence) %>
                <div
                  class="flex items-center gap-2 px-2 py-1.5 rounded border border-dashed border-amber-500/40 bg-amber-900/10 group"
                  style={"opacity: #{opacity}"}
                >
                  <%!-- Sparkle AI indicator --%>
                  <svg class="w-3 h-3 text-amber-400 flex-shrink-0" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 2L9.19 8.63 2 9.24l5.46 4.73L5.82 21 12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2z" />
                  </svg>
                  <%!-- Cue trigger button --%>
                  <button
                    phx-click="trigger_cue"
                    phx-target={@myself}
                    phx-value-deck={@deck_number}
                    phx-value-cue_id={cue.id}
                    class="flex-1 text-left text-xs text-white hover:text-amber-300 transition-colors truncate"
                    title={"#{cue.label || "Auto Cue"} @ #{format_ms(cue.position_ms)} (confidence: #{format_confidence(cue.confidence)})"}
                  >
                    <span class="font-mono text-amber-300/80 mr-1">{format_ms(cue.position_ms)}</span>
                    <span class="font-medium">{cue.label || "Auto Cue"}</span>
                  </button>
                  <%!-- Confidence badge --%>
                  <span class="text-[10px] text-amber-400/60 font-mono flex-shrink-0">
                    {format_confidence(cue.confidence)}
                  </span>
                  <%!-- Promote button --%>
                  <button
                    phx-click="promote_auto_cue"
                    phx-target={@myself}
                    phx-value-deck={@deck_number}
                    phx-value-cue_id={cue.id}
                    class="opacity-0 group-hover:opacity-100 px-1.5 py-0.5 text-[10px] font-bold rounded bg-green-700 text-green-200 hover:bg-green-600 transition-all"
                    title="Promote to manual cue"
                  >
                    KEEP
                  </button>
                  <%!-- Dismiss button --%>
                  <button
                    phx-click="dismiss_auto_cue"
                    phx-target={@myself}
                    phx-value-deck={@deck_number}
                    phx-value-cue_id={cue.id}
                    class="opacity-0 group-hover:opacity-100 text-gray-600 hover:text-red-400 transition-all text-xs px-0.5"
                    title="Dismiss this auto cue"
                  >
                    x
                  </button>
                </div>
              <% end %>
            </div>
          <% else %>
            <p :if={!@detecting_cues && @deck.track} class="text-xs text-gray-600 italic text-center py-1">
              No auto-generated cues. Click AUTO-DETECT to analyze.
            </p>
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

      <%!-- Stem Loops Panel --%>
      <.stem_loops_panel
        :if={@deck.track && length(@deck.stems || []) > 0}
        deck_number={@deck_number}
        deck={@deck}
        stem_loops={@stem_loops}
        stem_loops_open={@stem_loops_open}
        myself={@myself}
      />
    </div>
    """
  end

  # -- Stem Loops Sub-Component --

  attr :deck_number, :integer, required: true
  attr :deck, :map, required: true
  attr :stem_loops, :list, default: []
  attr :stem_loops_open, :boolean, default: false
  attr :myself, :any, required: true

  defp stem_loops_panel(assigns) do
    grouped_stems = group_stems_by_type(assigns.deck.stems || [])
    assigns = assign(assigns, :grouped_stems, grouped_stems)

    ~H"""
    <div class="mt-3 border border-gray-700/50 rounded-lg overflow-hidden">
      <%!-- Collapsible Header --%>
      <button
        phx-click="toggle_stem_loops"
        phx-target={@myself}
        phx-value-deck={@deck_number}
        class="w-full flex items-center justify-between px-3 py-2 bg-gray-800/50 hover:bg-gray-800 transition-colors"
      >
        <span class="flex items-center gap-2">
          <svg class="w-4 h-4 text-purple-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2z" />
          </svg>
          <span class="text-xs font-semibold text-gray-300 uppercase tracking-wider">
            Stem Loops
          </span>
          <span :if={length(@stem_loops) > 0} class="text-xs text-purple-400 font-mono">
            ({length(@stem_loops)})
          </span>
        </span>
        <svg
          class={"w-4 h-4 text-gray-500 transition-transform " <> if(@stem_loops_open, do: "rotate-180", else: "")}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          stroke-width="2"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      <%!-- Panel Content --%>
      <div :if={@stem_loops_open} class="px-3 py-2 space-y-3 bg-gray-900/50">
        <%= if @grouped_stems == [] do %>
          <p class="text-xs text-gray-600 italic py-2 text-center">
            No stems available. Run stem separation first.
          </p>
        <% else %>
          <%!-- Stem Groups --%>
          <div :for={{stem_type, stems} <- @grouped_stems} class="space-y-1.5">
            <%!-- Stem Type Header --%>
            <div class="flex items-center gap-2">
              <div
                class="w-2 h-2 rounded-full flex-shrink-0"
                style={"background-color: #{stem_type_color(stem_type)}"}
              >
              </div>
              <span
                class="text-xs font-bold uppercase tracking-wider"
                style={"color: #{stem_type_color(stem_type)}"}
              >
                {stem_type_label(stem_type)}
              </span>
              <div class="flex-1 border-t border-gray-700/30"></div>
            </div>

            <%!-- Per-Stem Entries --%>
            <div :for={stem <- stems} class="pl-4 space-y-1">
              <%!-- Stem Mini Waveform Bar --%>
              <div class="relative h-6 bg-gray-800 rounded overflow-hidden group">
                <%!-- Background bar --%>
                <div
                  class="absolute inset-0 opacity-20"
                  style={"background: linear-gradient(90deg, #{stem_type_color(stem_type)}22, #{stem_type_color(stem_type)}44, #{stem_type_color(stem_type)}22)"}
                >
                </div>
                <%!-- Loop regions overlay --%>
                <%= for loop <- stem_loops_for_stem(@stem_loops, stem.id) do %>
                  <% duration_ms = max((@deck.tempo_bpm || 120.0) / 120.0 * 240_000, 1) %>
                  <% left_pct = min(loop.start_ms / duration_ms * 100, 100) %>
                  <% width_pct = min((loop.end_ms - loop.start_ms) / duration_ms * 100, 100) %>
                  <button
                    phx-click="set_stem_loop_as_deck_loop"
                    phx-target={@myself}
                    phx-value-deck={@deck_number}
                    phx-value-loop_id={loop.id}
                    class="absolute top-0 bottom-0 cursor-pointer hover:brightness-125 transition-all"
                    style={"left: #{left_pct}%; width: #{width_pct}%; background-color: #{loop.color || stem_type_color(stem_type)}; opacity: 0.5;"}
                    title={"#{loop.label || "Loop"}: #{format_ms(loop.start_ms)} - #{format_ms(loop.end_ms)}"}
                  >
                  </button>
                <% end %>
                <%!-- Stem label --%>
                <span class="absolute left-1.5 top-1/2 -translate-y-1/2 text-[10px] text-gray-400 font-mono pointer-events-none">
                  {String.slice(to_string(stem.stem_type), 0, 6)}
                </span>
              </div>

              <%!-- Stem Loop Actions --%>
              <div class="flex items-center gap-1.5 text-[10px]">
                <%!-- Existing loops for this stem --%>
                <div :for={loop <- stem_loops_for_stem(@stem_loops, stem.id)} class="flex items-center gap-0.5">
                  <button
                    phx-click="audition_stem_loop"
                    phx-target={@myself}
                    phx-value-deck={@deck_number}
                    phx-value-loop_id={loop.id}
                    class="px-1.5 py-0.5 rounded text-white hover:brightness-125 transition-colors font-mono"
                    style={"background-color: #{loop.color || stem_type_color(stem_type)}; opacity: 0.8;"}
                    title={"Audition: #{loop.label}"}
                  >
                    {loop.label || "Loop"}
                  </button>
                  <button
                    phx-click="delete_stem_loop"
                    phx-target={@myself}
                    phx-value-deck={@deck_number}
                    phx-value-loop_id={loop.id}
                    class="text-gray-600 hover:text-red-400 transition-colors px-0.5"
                    title="Delete loop"
                  >
                    x
                  </button>
                </div>

                <%!-- Send to Pad Button --%>
                <button
                  phx-click="send_to_pad"
                  phx-target={@myself}
                  phx-value-stem_id={stem.id}
                  class="px-1.5 py-0.5 bg-gray-700 text-gray-400 hover:bg-cyan-600 hover:text-white rounded transition-colors"
                  title="Send this stem to the next empty pad"
                >
                  Pad
                </button>

                <%!-- Create Loop Button --%>
                <button
                  :if={@deck.loop_start_ms && @deck.loop_end_ms}
                  phx-click="create_stem_loop"
                  phx-target={@myself}
                  phx-value-deck={@deck_number}
                  phx-value-stem_id={stem.id}
                  phx-value-start_ms={@deck.loop_start_ms}
                  phx-value-end_ms={@deck.loop_end_ms}
                  class="ml-auto px-1.5 py-0.5 bg-gray-700 text-gray-400 hover:bg-purple-600 hover:text-white rounded transition-colors"
                  title={"Save current loop (#{format_ms(@deck.loop_start_ms)}-#{format_ms(@deck.loop_end_ms)}) to this stem"}
                >
                  + Save Loop
                </button>
                <span
                  :if={is_nil(@deck.loop_start_ms) || is_nil(@deck.loop_end_ms)}
                  class="ml-auto text-gray-600 italic"
                >
                  Set deck loop first
                </span>
              </div>
            </div>
          </div>
        <% end %>
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

  defp stem_loops_assign_key(1), do: :deck_1_stem_loops
  defp stem_loops_assign_key(2), do: :deck_2_stem_loops

  defp stem_loops_open_key(1), do: :deck_1_stem_loops_open
  defp stem_loops_open_key(2), do: :deck_2_stem_loops_open

  defp detecting_cues_key(1), do: :detecting_cues_deck_1
  defp detecting_cues_key(2), do: :detecting_cues_deck_2

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

  defp parse_integer(val) when is_integer(val), do: val

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_integer(_), do: 0

  @stem_type_colors %{
    vocals: "#FF6B6B",
    drums: "#4ECDC4",
    bass: "#45B7D1",
    other: "#96CEB4",
    piano: "#DDA0DD",
    guitar: "#F4A460",
    electric_guitar: "#F4A460",
    acoustic_guitar: "#D2691E",
    synth: "#9B59B6",
    strings: "#E6B800",
    wind: "#87CEEB"
  }

  defp stem_type_color(stem_type) when is_atom(stem_type) do
    Map.get(@stem_type_colors, stem_type, "#96CEB4")
  end

  defp stem_type_color(stem_type) when is_binary(stem_type) do
    atom =
      try do
        String.to_existing_atom(stem_type)
      rescue
        ArgumentError -> nil
      end

    if atom, do: stem_type_color(atom), else: "#96CEB4"
  end

  defp stem_type_color(_), do: "#96CEB4"

  defp group_stems_by_type(stems) when is_list(stems) do
    stems
    |> Enum.group_by(& &1.stem_type)
    |> Enum.sort_by(fn {type, _} -> stem_type_sort_order(type) end)
  end

  defp group_stems_by_type(_), do: []

  defp stem_type_sort_order(:vocals), do: 0
  defp stem_type_sort_order(:drums), do: 1
  defp stem_type_sort_order(:bass), do: 2
  defp stem_type_sort_order(:other), do: 3
  defp stem_type_sort_order(:piano), do: 4
  defp stem_type_sort_order(:guitar), do: 5
  defp stem_type_sort_order(:electric_guitar), do: 6
  defp stem_type_sort_order(:acoustic_guitar), do: 7
  defp stem_type_sort_order(:synth), do: 8
  defp stem_type_sort_order(:strings), do: 9
  defp stem_type_sort_order(:wind), do: 10
  defp stem_type_sort_order(_), do: 99

  defp stem_type_label(:vocals), do: "Vocals"
  defp stem_type_label(:drums), do: "Drums"
  defp stem_type_label(:bass), do: "Bass"
  defp stem_type_label(:other), do: "Other"
  defp stem_type_label(:piano), do: "Piano"
  defp stem_type_label(:guitar), do: "Guitar"
  defp stem_type_label(:electric_guitar), do: "E. Guitar"
  defp stem_type_label(:acoustic_guitar), do: "A. Guitar"
  defp stem_type_label(:synth), do: "Synth"
  defp stem_type_label(:strings), do: "Strings"
  defp stem_type_label(:wind), do: "Wind"
  defp stem_type_label(other), do: Phoenix.Naming.humanize(to_string(other))

  defp stem_loops_for_stem(stem_loops, stem_id) do
    Enum.filter(stem_loops, fn sl -> sl.stem_id == stem_id end)
  end

  defp confidence_to_opacity(confidence) when is_number(confidence) and confidence >= 0.9, do: 1.0
  defp confidence_to_opacity(confidence) when is_number(confidence) and confidence >= 0.7, do: 0.8
  defp confidence_to_opacity(confidence) when is_number(confidence), do: 0.6
  defp confidence_to_opacity(_), do: 0.8

  defp format_confidence(confidence) when is_number(confidence) do
    pct = trunc(confidence * 100)
    "#{pct}%"
  end

  defp format_confidence(_), do: "--"

  defp format_ms(ms) when is_integer(ms) and ms >= 0 do
    total_seconds = div(ms, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    millis = rem(ms, 1000) |> div(10)

    "#{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}.#{String.pad_leading(to_string(millis), 2, "0")}"
  end

  defp format_ms(_), do: "00:00.00"

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

  # -- Chef Helpers --

  defp recipe_to_map(%Chef.Recipe{} = recipe) do
    %{
      prompt: recipe.prompt,
      parsed_intent: recipe.parsed_intent,
      tracks: recipe.tracks,
      deck_assignments: recipe.deck_assignments,
      cue_plan: recipe.cue_plan,
      stems_to_load: recipe.stems_to_load,
      mixing_notes: recipe.mixing_notes,
      generated_at: recipe.generated_at
    }
  end

  defp recipe_to_map(other), do: other

  defp find_recipe_track(tracks, track_id) when is_list(tracks) do
    Enum.find(tracks, fn t ->
      (t[:track_id] || t["track_id"]) == track_id
    end)
  end

  defp find_recipe_track(_, _), do: nil

  defp format_recipe_tempo(tempo) when is_float(tempo), do: :erlang.float_to_binary(tempo, decimals: 1)
  defp format_recipe_tempo(tempo) when is_integer(tempo), do: "#{tempo}.0"
  defp format_recipe_tempo(_), do: "---"

  defp humanize_chef_error(:missing_api_key), do: "Anthropic API key not configured. Set ANTHROPIC_API_KEY in your environment."
  defp humanize_chef_error(:no_analysed_tracks), do: "No analysed tracks found. Analyse some tracks first, then try again."
  defp humanize_chef_error(reason) when is_binary(reason), do: reason
  defp humanize_chef_error(reason), do: "Something went wrong: #{inspect(reason)}"
end
