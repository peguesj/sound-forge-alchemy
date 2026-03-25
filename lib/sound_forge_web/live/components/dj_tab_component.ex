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
  alias SoundForge.DJ.{Chef, Presets, Timecode, CueSets}
  alias SoundForge.DJ.PresetsContext
  alias SoundForge.DJ.Layouts.Rekordbox
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
     |> assign(:deck_3_volume, 100)
     |> assign(:deck_4_volume, 100)
     |> assign(:deck_1, empty_deck_state())
     |> assign(:deck_2, empty_deck_state())
     |> assign(:deck_3, empty_deck_state())
     |> assign(:deck_4, empty_deck_state())
     |> assign(:deck_1_cue_points, [])
     |> assign(:deck_2_cue_points, [])
     |> assign(:deck_3_cue_points, [])
     |> assign(:deck_4_cue_points, [])
     |> assign(:deck_1_stem_loops, [])
     |> assign(:deck_2_stem_loops, [])
     |> assign(:deck_3_stem_loops, [])
     |> assign(:deck_4_stem_loops, [])
     |> assign(:deck_1_stem_loops_open, false)
     |> assign(:deck_2_stem_loops_open, false)
     |> assign(:deck_3_stem_loops_open, false)
     |> assign(:deck_4_stem_loops_open, false)
     |> assign(:detecting_cues_deck_1, false)
     |> assign(:detecting_cues_deck_2, false)
     |> assign(:detecting_cues_deck_3, false)
     |> assign(:detecting_cues_deck_4, false)
     |> assign(:metronome_active, false)
     |> assign(:metronome_volume, 60)
     |> assign(:preset_section_open, false)
     |> assign(:chef_panel_open, false)
     |> assign(:chef_prompt, "")
     |> assign(:chef_cooking, false)
     |> assign(:chef_progress_message, nil)
     |> assign(:chef_recipe, nil)
     |> assign(:chef_error, nil)
     |> assign(:deck_1_chef_type, "hot_cue_set")
     |> assign(:deck_2_chef_type, "hot_cue_set")
     |> assign(:deck_1_cue_sort, "confidence")
     |> assign(:deck_2_cue_sort, "confidence")
     |> assign(:deck_1_cue_page, 1)
     |> assign(:deck_2_cue_page, 1)
     |> assign(:deck_1_cue_per_page, 8)
     |> assign(:deck_2_cue_per_page, 8)
     |> assign(:deck_1_chef_sets, [])
     |> assign(:deck_2_chef_sets, [])
     |> assign(:initialized, false)
     |> assign(:browser_open, false)
     |> assign(:browser_search, "")
     |> assign(:master_volume, 85)
     |> assign(:presets_panel_open, false)
     |> assign(:deck_1_grid_mode, "bar")
     |> assign(:deck_2_grid_mode, "bar")
     |> assign(:deck_1_grid_fraction, "1/4")
     |> assign(:deck_2_grid_fraction, "1/4")
     |> assign(:deck_1_leading_stem, "drums")
     |> assign(:deck_2_leading_stem, "drums")
     |> assign(:deck_1_rhythmic_quantize, false)
     |> assign(:deck_2_rhythmic_quantize, false)
     |> assign(:deck_1_deck_type, "full")
     |> assign(:deck_2_deck_type, "full")
     |> assign(:deck_3_deck_type, "loop")
     |> assign(:deck_4_deck_type, "loop")
     |> assign(:master_deck_number, nil)
     |> assign(:deck_1_key_lock, false)
     |> assign(:deck_2_key_lock, false)
     |> assign(:deck_3_key_lock, false)
     |> assign(:deck_4_key_lock, false)
     |> assign(:crossfader_split, false)
     |> assign(:deck_3_loop_pads, default_loop_pads())
     |> assign(:deck_4_loop_pads, default_loop_pads())
     |> assign(:deck_3_pad_mode, "loop")
     |> assign(:deck_4_pad_mode, "loop")
     |> assign(:deck_3_poly_voices, 1)
     |> assign(:deck_4_poly_voices, 1)
     |> assign(:deck_3_pad_fade, "none")
     |> assign(:deck_4_pad_fade, "none")
     |> assign(:deck_3_active_pads, [])
     |> assign(:deck_4_active_pads, [])
     |> assign(:alchemy_sets, [])
     |> assign(:dj_midi_learn_mode, false)
     |> assign(:dj_midi_learn_target, nil)
     |> assign(:saved_presets, [])
     |> assign(:preset_name_input, "")
     |> assign(:rekordbox_import_result, nil)
     |> allow_upload(:preset_file,
       accept: ~w(.tsi .touchosc),
       max_entries: 1,
       max_file_size: 5_000_000
     )
     |> allow_upload(:rekordbox_file,
       accept: ~w(.xml),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def update(%{midi_event: {:bpm_update, external_bpm}}, socket) do
    socket =
      Enum.reduce([{:deck_1, 1}, {:deck_2, 2}, {:deck_3, 3}, {:deck_4, 4}], socket, fn {deck_key, deck_number}, acc ->
        deck = Map.get(acc.assigns, deck_key)

        if deck && deck.midi_sync && deck.track && deck.tempo_bpm > 0 do
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
      Enum.reduce([{:deck_1, 1}, {:deck_2, 2}, {:deck_3, 3}, {:deck_4, 4}], socket, fn {deck_key, deck_number}, acc ->
        deck = Map.get(acc.assigns, deck_key)

        if deck && deck.midi_sync && deck.track do
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
      user_id = assigns[:current_user_id]
      saved_presets = if user_id, do: PresetsContext.list_presets(user_id), else: []
      alchemy_sets = if user_id, do: SoundForge.BigLoopy.list_alchemy_sets(user_id), else: []

      socket =
        socket
        |> assign(tracks: tracks, initialized: true, saved_presets: saved_presets, alchemy_sets: alchemy_sets)
        |> restore_deck_from_db(user_id, 1)
        |> restore_deck_from_db(user_id, 2)

      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  # -- Events --

  @impl true
  # Form-based select (deck 3/4 soundboard): sends "track_id" (underscore).
  # Normalize to "track-id" (hyphen) and delegate to the main clause.
  def handle_event("load_track", %{"deck" => _d, "track_id" => _t} = params, socket)
      when not is_map_key(params, "track-id") do
    handle_event("load_track", Map.put(params, "track-id", params["track_id"]), socket)
  end

  def handle_event("load_track", %{"deck" => deck_str, "track-id" => track_id}, socket) do
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

          # Merge with empty_deck_state defaults so all new fields are always present
          deck_state =
            Map.merge(empty_deck_state(), %{
              track: track,
              playing: false,
              tempo_bpm: session.tempo_bpm || tempo || 0.0,
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
            })

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

      updated_deck = %{deck | loop_start_ms: loop_start, loop_end_ms: loop_end, loop_active: true, loop_size_beats: beats, loop_size_str: beats_str}

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

  # Tap tempo: client sends tapped BPM; server adjusts pitch_adjust so playback
  # rate matches the tapped tempo relative to the track's native BPM.
  @impl true
  def handle_event("tap_tempo", %{"deck" => deck_str, "bpm" => bpm_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    with {tapped_bpm, _} <- Float.parse(to_string(bpm_str)),
         true <- deck.tempo_bpm > 0 and tapped_bpm > 0 do
      pitch = ((tapped_bpm / deck.tempo_bpm - 1.0) * 100.0) |> max(-50.0) |> min(50.0)
      updated_deck = %{deck | pitch_adjust: pitch}
      user_id = socket.assigns[:current_user_id]
      persist_pitch(user_id, deck_number, pitch)

      socket =
        socket
        |> assign(deck_key, updated_deck)
        |> push_event("set_pitch", %{deck: deck_number, value: pitch})

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
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
  def handle_event("loop_from_cue", %{"deck" => deck_str, "cue_id" => cue_id}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    cue_points_key = cue_points_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    all_cues = Map.get(socket.assigns, cue_points_key, [])

    if deck.track do
      case DJ.get_cue_point(cue_id) do
        %DJ.CuePoint{} = cue ->
          loop_start_ms = cue.position_ms

          # Find the nearest auto-cue AFTER this position for loop end.
          # Fall back to a 4-beat interval if there is no next cue.
          next_cue =
            all_cues
            |> Enum.filter(& &1.auto_generated)
            |> Enum.filter(&(&1.position_ms > loop_start_ms))
            |> Enum.min_by(& &1.position_ms, fn -> nil end)

          loop_end_ms =
            if next_cue do
              next_cue.position_ms
            else
              beat_length_ms =
                if deck.tempo_bpm > 0,
                  do: round(4 * 60_000 / deck.tempo_bpm),
                  else: 4_000

              loop_start_ms + beat_length_ms
            end

          # Quantize loop in/out to beat grid
          bpm = deck.tempo_bpm || 0
          q_start_ms = quantize_to_beat(loop_start_ms, bpm)

          beat_length_ms = if bpm > 0, do: 60_000.0 / bpm, else: 500.0
          q_end_ms = quantize_to_beat(loop_end_ms, bpm)
          # Ensure loop has at least 1 beat length
          q_end_ms = max(q_end_ms, q_start_ms + round(beat_length_ms))

          position_sec = q_start_ms / 1000.0

          # Arm the loop WITHOUT auto-playing — user decides when to play
          updated_deck = %{
            deck
            | loop_start_ms: q_start_ms,
              loop_end_ms: q_end_ms,
              loop_active: true,
              position: position_sec
          }

          socket =
            socket
            |> assign(deck_key, updated_deck)
            |> push_event("seek_deck", %{deck: deck_number, position: position_sec})
            |> push_event("set_loop", %{
              deck: deck_number,
              loop_start_ms: q_start_ms,
              loop_end_ms: q_end_ms,
              active: true
            })

          {:noreply, socket}

        nil ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # -- Hot Cue A-H Pads --

  @impl true
  def handle_event("set_hot_cue", %{"deck" => deck_str, "letter" => letter}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    cue_points_key = cue_points_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    user_id = socket.assigns[:current_user_id]

    if deck.track && user_id do
      existing_cues = Map.get(socket.assigns, cue_points_key, [])
      hot_cues = Enum.filter(existing_cues, &(&1.cue_type == :hot && !&1.auto_generated))
      existing = Enum.find(hot_cues, &(&1.label == letter))

      if existing do
        # Jump to existing hot cue (no auto-play — seek only so user controls playback)
        position_sec = existing.position_ms / 1000.0
        {:noreply, push_event(socket, "seek_and_play", %{deck: deck_number, position: position_sec})}
      else
        # Create new hot cue at current playhead position
        position_ms = trunc(deck.position * 1000)
        color = hot_cue_color(letter)

        attrs = %{
          track_id: deck.track.id,
          user_id: user_id,
          position_ms: position_ms,
          label: letter,
          color: color,
          cue_type: :hot,
          auto_generated: false
        }

        case DJ.create_cue_point(attrs) do
          {:ok, cue_point} ->
            updated_cues = Enum.sort_by([cue_point | existing_cues], & &1.position_ms)

            socket =
              socket
              |> assign(cue_points_key, updated_cues)
              |> push_event("set_cue_points", %{
                deck: deck_number,
                cue_points: encode_cue_points(updated_cues)
              })

            {:noreply, socket}

          {:error, _} ->
            {:noreply, socket}
        end
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_hot_cue", %{"deck" => deck_str, "letter" => letter}, socket) do
    deck_number = String.to_integer(deck_str)
    cue_points_key = cue_points_assign_key(deck_number)
    existing_cues = Map.get(socket.assigns, cue_points_key, [])
    target = Enum.find(existing_cues, &(&1.cue_type == :hot && &1.label == letter))

    if target do
      case DJ.delete_cue_point(target) do
        {:ok, _} ->
          updated_cues = Enum.reject(existing_cues, &(&1.id == target.id))

          socket =
            socket
            |> assign(cue_points_key, updated_cues)
            |> push_event("set_cue_points", %{
              deck: deck_number,
              cue_points: encode_cue_points(updated_cues)
            })

          {:noreply, socket}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # -- Time Factor (Double / Half Time) --

  @impl true
  def handle_event("set_time_factor", %{"deck" => deck_str, "factor" => factor_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    factor = String.to_float(factor_str)
    updated_deck = %{deck | time_factor: factor}

    socket =
      socket
      |> assign(deck_key, updated_deck)
      |> push_event("set_time_factor", %{deck: deck_number, factor: factor})

    {:noreply, socket}
  end

  # -- EQ Kill Switches --

  @impl true
  def handle_event("toggle_eq_kill", %{"deck" => deck_str, "band" => band}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    new_kills = Map.update(deck.eq_kills, band, true, &(!&1))
    updated_deck = %{deck | eq_kills: new_kills}

    socket =
      socket
      |> assign(deck_key, updated_deck)
      |> push_event("set_eq_kill", %{deck: deck_number, band: band, active: new_kills[band]})

    {:noreply, socket}
  end

  # -- Stem Solo / Mute --

  @impl true
  def handle_event(
        "toggle_stem_state",
        %{"deck" => deck_str, "stem" => stem_type, "mode" => mode},
        socket
      ) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    current = Map.get(deck.stem_states, stem_type, "on")

    new_state =
      case {mode, current} do
        {"mute", "mute"} -> "on"
        {"mute", _} -> "mute"
        {"solo", "solo"} -> "on"
        {"solo", _} -> "solo"
        _ -> "on"
      end

    new_states = Map.put(deck.stem_states, stem_type, new_state)
    updated_deck = %{deck | stem_states: new_states}

    socket =
      socket
      |> assign(deck_key, updated_deck)
      |> push_event("set_stem_states", %{deck: deck_number, stem_states: new_states})

    {:noreply, socket}
  end

  # -- LP/HP Filter --

  @impl true
  def handle_event("set_filter", %{"deck" => deck_str, "mode" => mode, "cutoff" => cutoff_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)
    cutoff = String.to_float(cutoff_str)
    updated_deck = %{deck | filter_mode: mode, filter_cutoff: cutoff}

    socket =
      socket
      |> assign(deck_key, updated_deck)
      |> push_event("set_filter", %{deck: deck_number, mode: mode, cutoff: cutoff})

    {:noreply, socket}
  end

  # -- Metronome --

  @impl true
  def handle_event("toggle_metronome", _params, socket) do
    active = !socket.assigns.metronome_active
    # Use the BPM of deck 1 (master) for the click track
    bpm = socket.assigns.deck_1.tempo_bpm
    volume = socket.assigns.metronome_volume / 100.0

    socket =
      socket
      |> assign(:metronome_active, active)
      |> push_event("toggle_metronome", %{active: active, bpm: bpm, volume: volume})

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_metronome_volume", %{"volume" => vol_str}, socket) do
    volume = String.to_integer(vol_str)
    {:noreply, assign(socket, :metronome_volume, volume)}
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
    leading_stem = Map.get(socket.assigns, :"deck_#{deck_number}_leading_stem", "drums")

    if deck.track && user_id do
      case DJ.generate_auto_cues(deck.track.id, user_id, leading_stem: leading_stem) do
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

      leading_stem = Map.get(socket.assigns, :"deck_#{deck_number}_leading_stem", "drums")

      case DJ.generate_auto_cues(deck.track.id, user_id, leading_stem: leading_stem) do
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

  # -- Grid / Leading Stem / Rhythmic Quantize --

  @impl true
  def handle_event("set_grid_mode", %{"deck" => deck_str, "mode" => mode}, socket) do
    deck_number = String.to_integer(deck_str)
    grid_mode_key = :"deck_#{deck_number}_grid_mode"

    {:noreply,
     socket
     |> assign(grid_mode_key, mode)
     |> push_event("set_grid_mode", %{deck: deck_number, mode: mode})}
  end

  @impl true
  def handle_event("set_grid_fraction", %{"deck" => deck_str, "fraction" => fraction}, socket) do
    deck_number = String.to_integer(deck_str)
    key = :"deck_#{deck_number}_grid_fraction"

    {:noreply,
     socket
     |> assign(key, fraction)
     |> push_event("set_grid_fraction", %{deck: deck_number, fraction: fraction})}
  end

  @impl true
  def handle_event("set_deck_type", %{"deck" => deck_str, "deck_type" => deck_type}, socket) do
    deck_number = String.to_integer(deck_str)
    key = :"deck_#{deck_number}_deck_type"
    {:noreply, assign(socket, key, deck_type)}
  end

  # -- Loop Deck Pad Handlers --

  @impl true
  def handle_event("trigger_loop_pad", %{"deck" => deck_str, "pad" => pad_str}, socket) do
    deck_number = String.to_integer(deck_str)
    pad_index = String.to_integer(pad_str)
    pads_key = :"deck_#{deck_number}_loop_pads"
    active_key = :"deck_#{deck_number}_active_pads"
    mode_key = :"deck_#{deck_number}_pad_mode"
    poly_key = :"deck_#{deck_number}_poly_voices"
    deck_key = deck_assign_key(deck_number)

    pads = Map.get(socket.assigns, pads_key, default_loop_pads())
    pad = Enum.at(pads, pad_index)
    mode = Map.get(socket.assigns, mode_key, "loop")
    poly = Map.get(socket.assigns, poly_key, 1)
    deck = Map.get(socket.assigns, deck_key)
    active_pads = Map.get(socket.assigns, active_key, [])

    if pad && pad.assigned && deck && deck.track do
      position_sec = pad.position_ms / 1000.0

      # Enforce polyphony: deactivate oldest pads if at voice limit
      new_active =
        if pad_index in active_pads do
          List.delete(active_pads, pad_index)
        else
          capped = if length(active_pads) >= poly, do: tl(active_pads), else: active_pads
          capped ++ [pad_index]
        end

      socket =
        socket
        |> assign(active_key, new_active)
        |> push_event("loop_pad_trigger", %{
          deck: deck_number,
          pad: pad_index,
          position: position_sec,
          loop_end: pad.end_ms && pad.end_ms / 1000.0,
          mode: mode,
          fade: Map.get(socket.assigns, :"deck_#{deck_number}_pad_fade", "none")
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("assign_loop_pad", %{"deck" => deck_str, "pad" => pad_str}, socket) do
    deck_number = String.to_integer(deck_str)
    pad_index = String.to_integer(pad_str)
    deck_key = deck_assign_key(deck_number)
    pads_key = :"deck_#{deck_number}_loop_pads"
    deck = Map.get(socket.assigns, deck_key)

    if deck && deck.track do
      position_ms = trunc(deck.position * 1000)
      # Default loop end = 4 beats ahead
      bpm = if deck.tempo_bpm > 0, do: deck.tempo_bpm, else: 120.0
      beat_ms = trunc(60_000 / bpm)
      end_ms = position_ms + beat_ms * 4

      pads = Map.get(socket.assigns, pads_key, default_loop_pads())
      pad_colors = ~w(#7c3aed #2563eb #0891b2 #059669 #d97706 #dc2626 #db2777 #6d28d9)
      color = Enum.at(pad_colors, rem(pad_index, length(pad_colors)), "#7c3aed")

      updated_pads =
        List.update_at(pads, pad_index, fn _pad ->
          %{
            assigned: true,
            position_ms: position_ms,
            end_ms: end_ms,
            label: "#{format_ms(position_ms)}",
            color: color
          }
        end)

      {:noreply, assign(socket, pads_key, updated_pads)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_loop_pad", %{"deck" => deck_str, "pad" => pad_str}, socket) do
    deck_number = String.to_integer(deck_str)
    pad_index = String.to_integer(pad_str)
    pads_key = :"deck_#{deck_number}_loop_pads"
    active_key = :"deck_#{deck_number}_active_pads"

    pads = Map.get(socket.assigns, pads_key, default_loop_pads())
    updated = List.update_at(pads, pad_index, fn _ -> empty_pad() end)
    active = Map.get(socket.assigns, active_key, [])
    new_active = List.delete(active, pad_index)

    socket =
      socket
      |> assign(pads_key, updated)
      |> assign(active_key, new_active)

    {:noreply, socket}
  end

  @doc false
  def handle_event(
        "load_alchemy_set",
        %{"deck" => deck_str, "alchemy_set_id" => set_id},
        socket
      )
      when byte_size(set_id) > 0 do
    deck_number = String.to_integer(deck_str)
    pads_key = :"deck_#{deck_number}_loop_pads"

    case SoundForge.BigLoopy.get_alchemy_set(set_id) do
      nil ->
        {:noreply, socket}

      alchemy_set ->
        loops = get_in(alchemy_set.performance_set, ["loops"]) || []

        updated_pads =
          loops
          |> Enum.take(8)
          |> Enum.with_index()
          |> Enum.map(fn {loop, idx} ->
            %{
              assigned: true,
              position_ms: 0,
              label: Map.get(loop, "stem", "Loop #{idx + 1}"),
              color: "#7c3aed",
              loop_file: Map.get(loop, "path")
            }
          end)

        pads = default_loop_pads()
        merged = Enum.with_index(pads) |> Enum.map(fn {pad, i} ->
          Enum.at(updated_pads, i, pad)
        end)

        {:noreply, assign(socket, pads_key, merged)}
    end
  end

  def handle_event("load_alchemy_set", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_pad_mode", %{"deck" => deck_str, "mode" => mode}, socket) do
    deck_number = String.to_integer(deck_str)
    {:noreply, assign(socket, :"deck_#{deck_number}_pad_mode", mode)}
  end

  @impl true
  def handle_event("set_pad_poly", %{"deck" => deck_str, "voices" => voices_str}, socket) do
    deck_number = String.to_integer(deck_str)
    voices = String.to_integer(voices_str)
    {:noreply, assign(socket, :"deck_#{deck_number}_poly_voices", voices)}
  end

  @impl true
  def handle_event("set_pad_fade", %{"deck" => deck_str, "fade" => fade}, socket) do
    deck_number = String.to_integer(deck_str)
    {:noreply, assign(socket, :"deck_#{deck_number}_pad_fade", fade)}
  end

  @impl true
  def handle_event("open_kit_browser", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    {:noreply, assign(socket, :kit_browser_deck, deck_number)}
  end

  @impl true
  def handle_event("load_drum_kit", %{"deck" => deck_str, "kit_id" => kit_id}, socket) do
    deck_number = String.to_integer(deck_str)

    case SoundForge.Music.get_drum_kit(kit_id) do
      nil ->
        {:noreply, socket}

      kit ->
        # Assign each kit slot to the corresponding pad
        updated =
          Enum.reduce(kit.slots, socket, fn slot, acc ->
            pad_idx = Map.get(slot, "slot", 0)
            track_id = Map.get(slot, "track_id")
            label = Map.get(slot, "label")

            if track_id do
              pads_key = :"deck_#{deck_number}_loop_pads"
              pads = Map.get(acc.assigns, pads_key, [])

              new_pad = %{
                assigned: true,
                track_id: track_id,
                position_ms: 0,
                label: label || "KIT #{pad_idx + 1}",
                color: "#7c3aed"
              }

              new_pads =
                List.update_at(pads, pad_idx, fn _ -> new_pad end)
                |> then(fn ps ->
                  if length(ps) <= pad_idx do
                    ps ++ List.duplicate(%{assigned: false, position_ms: 0, label: nil, color: "#374151"}, pad_idx - length(ps) + 1)
                  else
                    ps
                  end
                end)

              assign(acc, pads_key, new_pads)
            else
              acc
            end
          end)

        {:noreply, assign(updated, :kit_browser_deck, nil)}
    end
  end

  @impl true
  def handle_event("drop_splice_on_pad", %{"deck" => deck_str, "pad" => pad_str, "track_id" => track_id}, socket) do
    deck_number = String.to_integer(deck_str)
    pad_idx = String.to_integer(pad_str)
    pads_key = :"deck_#{deck_number}_loop_pads"
    pads = Map.get(socket.assigns, pads_key, [])

    track = case SoundForge.Music.get_track(track_id) do
      {:ok, t} -> t
      _ -> nil
    end
    label = if track, do: (track.title || Path.basename(track.spotify_url || "", ".wav")), else: "PAD #{pad_idx + 1}"

    new_pad = %{
      assigned: true,
      track_id: String.to_integer(track_id),
      position_ms: 0,
      label: String.slice(label, 0, 12),
      color: "#0e7490"
    }

    new_pads =
      if length(pads) > pad_idx do
        List.update_at(pads, pad_idx, fn _ -> new_pad end)
      else
        pads ++ List.duplicate(%{assigned: false, position_ms: 0, label: nil, color: "#374151"}, pad_idx - length(pads)) ++ [new_pad]
      end

    {:noreply, assign(socket, pads_key, new_pads)}
  end

  @impl true
  def handle_event("set_master_deck", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    current_master = socket.assigns.master_deck_number

    new_master = if current_master == deck_number, do: nil, else: deck_number
    {:noreply, assign(socket, :master_deck_number, new_master)}
  end

  @impl true
  def handle_event("toggle_key_lock", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    key = :"deck_#{deck_number}_key_lock"
    {:noreply, assign(socket, key, !Map.get(socket.assigns, key, false))}
  end

  @impl true
  def handle_event("toggle_crossfader_split", _params, socket) do
    {:noreply, assign(socket, :crossfader_split, !socket.assigns.crossfader_split)}
  end

  # -- Chef Cue Set Handlers --

  @impl true
  def handle_event("set_chef_type", %{"deck" => deck_str, "chef_type" => chef_type}, socket) do
    deck_number = String.to_integer(deck_str)
    {:noreply, assign(socket, :"deck_#{deck_number}_chef_type", chef_type)}
  end

  @impl true
  def handle_event("set_cue_sort", %{"deck" => deck_str, "sort" => sort}, socket) do
    deck_number = String.to_integer(deck_str)
    {:noreply,
     socket
     |> assign(:"deck_#{deck_number}_cue_sort", sort)
     |> assign(:"deck_#{deck_number}_cue_page", 1)}
  end

  @impl true
  def handle_event("cue_page", %{"deck" => deck_str, "page" => page_str}, socket) do
    deck_number = String.to_integer(deck_str)
    page = String.to_integer(page_str)
    {:noreply, assign(socket, :"deck_#{deck_number}_cue_page", max(1, page))}
  end

  @impl true
  def handle_event("generate_chef_set", %{"deck" => deck_str} = params, socket) do
    deck_number = String.to_integer(deck_str)
    deck = Map.get(socket.assigns, :"deck_#{deck_number}")
    user_id = socket.assigns[:current_user_id]
    chef_type = Map.get(params, "chef_type", Map.get(socket.assigns, :"deck_#{deck_number}_chef_type", "hot_cue_set"))

    if deck && deck.track && user_id do
      leading_stem = Map.get(socket.assigns, :"deck_#{deck_number}_leading_stem", "drums")

      case CueSets.generate_chef_set(deck.track.id, user_id,
             type: chef_type,
             leading_stem: leading_stem,
             name: "Chef #{chef_type} #{Date.utc_today()}"
           ) do
        {:ok, _job} ->
          {:noreply,
           socket
           |> assign(:"detecting_cues_deck_#{deck_number}", true)
           |> put_flash(:info, "Chef is generating #{chef_type} for Deck #{deck_letter(deck_number)}...")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Chef generation failed")}
      end
    else
      {:noreply, put_flash(socket, :error, "Load a track first")}
    end
  end

  @impl true
  def handle_event("load_chef_set", %{"deck" => deck_str, "set_id" => set_id}, socket) do
    deck_number = String.to_integer(deck_str)
    user_id = socket.assigns[:current_user_id]

    case CueSets.get_chef_set(set_id, user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Chef set not found")}

      chef_set ->
        items = CueSets.list_chef_set_items(chef_set.id, per_page: 100)
        cue_key = :"deck_#{deck_number}_cue_points"
        existing = Map.get(socket.assigns, cue_key, [])

        new_cues =
          Enum.map(items.items, fn item ->
            %{
              id: item.id,
              position_ms: item.position_ms,
              label: item.label || "C",
              cue_type: :hot,
              auto_generated: true,
              confidence: item.confidence || 1.0,
              color: item.color || "#6366f1"
            }
          end)

        merged = (Enum.reject(existing, & &1.auto_generated) ++ new_cues)

        {:noreply,
         socket
         |> assign(cue_key, merged)
         |> push_event("set_cue_points", %{deck: deck_number, cue_points: encode_cue_points(merged)})
         |> put_flash(:info, "Loaded Chef set: #{chef_set.name}")}
    end
  end

  @impl true
  def handle_event("delete_chef_set", %{"set_id" => set_id}, socket) do
    user_id = socket.assigns[:current_user_id]

    case CueSets.delete_chef_set(set_id, user_id) do
      {:ok, _} ->
        track_1_id = socket.assigns.deck_1.track && socket.assigns.deck_1.track.id
        track_2_id = socket.assigns.deck_2.track && socket.assigns.deck_2.track.id
        sets_1 = if track_1_id, do: CueSets.list_chef_sets(user_id, track_1_id), else: []
        sets_2 = if track_2_id, do: CueSets.list_chef_sets(user_id, track_2_id), else: []
        {:noreply,
         socket
         |> assign(:deck_1_chef_sets, sets_1)
         |> assign(:deck_2_chef_sets, sets_2)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete Chef set")}
    end
  end

  @impl true
  def handle_event("set_leading_stem", %{"deck" => deck_str, "stem" => stem}, socket) do
    deck_number = String.to_integer(deck_str)
    {:noreply, assign(socket, :"deck_#{deck_number}_leading_stem", stem)}
  end

  @impl true
  def handle_event("toggle_rhythmic_quantize", %{"deck" => deck_str}, socket) do
    deck_number = String.to_integer(deck_str)
    rq_key = :"deck_#{deck_number}_rhythmic_quantize"
    new_val = !Map.get(socket.assigns, rq_key, false)

    {:noreply,
     socket
     |> assign(rq_key, new_val)
     |> push_event("set_rhythmic_quantize", %{deck: deck_number, enabled: new_val})}
  end

  # -- DJ MIDI Learn Mode --

  @impl true
  def handle_event("toggle_dj_midi_learn", _params, socket) do
    new_mode = !socket.assigns.dj_midi_learn_mode

    if new_mode do
      {:noreply,
       socket
       |> assign(:dj_midi_learn_mode, true)
       |> assign(:dj_midi_learn_target, nil)
       |> push_event("enter_dj_midi_learn", %{})}
    else
      {:noreply,
       socket
       |> assign(:dj_midi_learn_mode, false)
       |> assign(:dj_midi_learn_target, nil)
       |> push_event("exit_dj_midi_learn", %{})}
    end
  end

  @impl true
  def handle_event("dj_learn_control", params, socket) do
    target = %{
      "action" => params["action"],
      "deck" => params["deck"],
      "slot" => params["slot"]
    }

    {:noreply,
     socket
     |> assign(:dj_midi_learn_target, target)
     |> push_event("enter_dj_midi_learn", %{target: target})}
  end

  @impl true
  def handle_event(
        "dj_midi_learned",
        %{
          "device_name" => device_name,
          "midi_type" => midi_type_str,
          "channel" => channel,
          "number" => number,
          "action" => action_str
        } = params,
        socket
      ) do
    user_id = socket.assigns[:current_user_id]

    if user_id do
      midi_type = String.to_existing_atom(midi_type_str)
      action = String.to_existing_atom(action_str)

      mapping_params =
        %{}
        |> then(fn p -> if params["deck"], do: Map.put(p, "deck", params["deck"]), else: p end)
        |> then(fn p -> if params["slot"], do: Map.put(p, "slot", params["slot"]), else: p end)

      attrs = %{
        user_id: user_id,
        device_name: device_name,
        midi_type: midi_type,
        channel: channel,
        number: number,
        action: action,
        params: mapping_params,
        source: "dj_learn"
      }

      SoundForge.MIDI.Mappings.upsert_dj_mapping(attrs)
    end

    # Stay in learn mode, clear target so next control can be assigned
    {:noreply,
     socket
     |> assign(:dj_midi_learn_target, nil)
     |> push_event("dj_learn_assignment_saved", %{action: action_str})}
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
                  tempo_bpm: session.tempo_bpm || tempo || 0.0,
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

  # -- Master Volume (US-012) --

  @impl true
  def handle_event("set_master_volume", %{"value" => value_str}, socket) do
    value = value_str |> String.to_integer() |> max(0) |> min(100)

    {:noreply,
     socket
     |> assign(:master_volume, value)
     |> push_event("set_master_volume", %{value: value})}
  end

  @impl true
  def handle_event(
        "set_eq_gain_deck_" <> deck_band,
        %{"deck" => deck_str, "band" => band, "gain" => gain_str},
        socket
      ) do
    _ = deck_band
    deck = String.to_integer(deck_str)

    case Float.parse(gain_str) do
      {gain, _} ->
        {:noreply, push_event(socket, "set_eq_gain", %{deck: deck, band: band, gain: gain})}

      :error ->
        {:noreply, socket}
    end
  end

  # -- Saved Presets Panel (US-009) --

  @impl true
  def handle_event("toggle_presets_panel", _params, socket) do
    {:noreply, assign(socket, :presets_panel_open, !socket.assigns.presets_panel_open)}
  end

  @impl true
  def handle_event("preset_name_change", %{"value" => value}, socket) do
    {:noreply, assign(socket, :preset_name_input, value)}
  end

  @impl true
  def handle_event("save_preset", _params, socket) do
    name = String.trim(socket.assigns.preset_name_input)
    user_id = socket.assigns[:current_user_id]

    if name != "" && user_id do
      case PresetsContext.save_current_layout(name, socket.assigns) do
        {:ok, _preset} ->
          saved_presets = PresetsContext.list_presets(user_id)

          {:noreply,
           socket
           |> assign(:saved_presets, saved_presets)
           |> assign(:preset_name_input, "")
           |> put_flash(:info, "Preset \"#{name}\" saved")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to save preset")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("load_preset", %{"id" => preset_id}, socket) do
    user_id = socket.assigns[:current_user_id]

    case PresetsContext.load_layout(preset_id, user_id) do
      {:ok, new_assigns} ->
        socket =
          socket
          |> assign(new_assigns)
          |> put_flash(:info, "Preset loaded")

        socket =
          Enum.reduce([{:deck_1, 1}, {:deck_2, 2}], socket, fn {deck_key, deck_num}, acc ->
            deck = Map.get(acc.assigns, deck_key)

            if deck && deck.track && deck.audio_urls != [] do
              push_event(acc, "load_deck_audio", %{
                deck: deck_num,
                urls: deck.audio_urls
              })
            else
              acc
            end
          end)

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Preset not found")}

      {:error, :invalid_layout} ->
        {:noreply, put_flash(socket, :error, "Preset layout is invalid")}
    end
  end

  @impl true
  def handle_event("delete_preset", %{"id" => preset_id}, socket) do
    user_id = socket.assigns[:current_user_id]

    case PresetsContext.delete_preset(preset_id, user_id) do
      :ok ->
        saved_presets = PresetsContext.list_presets(user_id)
        {:noreply, assign(socket, :saved_presets, saved_presets)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Preset not found")}
    end
  end

  # -- JSON Export (US-011) --

  @impl true
  def handle_event("export_preset", _params, socket) do
    layout_json = PresetsContext.build_layout_json(socket.assigns)
    json_string = Jason.encode!(layout_json, pretty: true)
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d%H%M%S")
    filename = "sfa-layout-#{timestamp}.json"

    {:noreply, push_event(socket, "download_file", %{filename: filename, content: json_string, mime: "application/json"})}
  end

  # -- Rekordbox XML Import (US-010) --

  @impl true
  def handle_event("validate_rekordbox", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("import_rekordbox", _params, socket) do
    user_id = socket.assigns[:current_user_id]

    results =
      consume_uploaded_entries(socket, :rekordbox_file, fn %{path: path}, _entry ->
        binary = File.read!(path)
        Rekordbox.parse(binary)
      end)

    case results do
      [{:ok, %{tracks: rb_tracks, playlists: rb_playlists}}] ->
        {matched_count, total_count, cues_created} =
          Enum.reduce(rb_tracks, {0, 0, 0}, fn rb_track, {matched, total, cues} ->
            total = total + 1
            name = rb_track[:name] || ""
            artist = rb_track[:artist] || ""

            db_tracks =
              if name != "" do
                results = Music.search_tracks(name)

                # Prefer exact artist match; fall back to title-only match
                artist_lower = String.downcase(artist)

                exact = Enum.filter(results, fn t ->
                  String.downcase(t.artist || "") == artist_lower
                end)

                if exact != [], do: exact, else: results
              else
                []
              end

            case db_tracks do
              [] ->
                {matched, total, cues}

              [db_track | _] ->
                new_cues =
                  rb_track[:cue_points]
                  |> Enum.filter(fn c -> c.type_atom in [:hot_cue, :memory_cue] end)
                  |> Enum.reduce(0, fn cue, count ->
                    case DJ.create_cue_point(%{
                           track_id: db_track.id,
                           user_id: user_id,
                           position_ms: cue.start_ms,
                           label: cue.name || "",
                           cue_type: cue.type_atom,
                           color: "#8b5cf6"
                         }) do
                      {:ok, _} -> count + 1
                      {:error, _} -> count
                    end
                  end)

                {matched + 1, total, cues + new_cues}
            end
          end)

        # Pre-fill chef_prompt with first playlist name if currently empty
        first_playlist_name =
          case rb_playlists do
            [%{name: name} | _] when name != "" -> name
            _ -> nil
          end

        socket =
          socket
          |> assign(:rekordbox_import_result, %{
            matched_tracks: matched_count,
            total_tracks: total_count,
            cues_created: cues_created
          })
          |> put_flash(
            :info,
            "Imported #{cues_created} cues from #{matched_count}/#{total_count} tracks"
          )

        socket =
          if first_playlist_name && String.trim(socket.assigns.chef_prompt) == "" do
            assign(socket, :chef_prompt, first_playlist_name)
          else
            socket
          end

        {:noreply, socket}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, "Rekordbox import failed: #{inspect(reason)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "No file uploaded")}
    end
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
      [{:ok, %{mappings: mapping_attrs}}] ->
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

      [{:ok, mapping_attrs}] when is_list(mapping_attrs) ->
        # Backward-compat: plain list
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

        stem = Enum.find(deck.stems || [], &(to_string(&1.id) == to_string(stem_loop.stem_id)))
        stem_type = if stem, do: to_string(stem.stem_type), else: "other"
        steps = stem_loop.steps || List.duplicate(true, 8)

        socket =
          socket
          |> assign(deck_key, updated_deck)
          |> push_event("set_loop", %{
            deck: deck_number,
            loop_start_ms: stem_loop.start_ms,
            loop_end_ms: stem_loop.end_ms,
            active: true
          })
          |> push_event("set_stem_loop_gate", %{
            deck: deck_number,
            stem_type: stem_type,
            steps: steps
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

  # Toggle a single step (0–7) on a stem loop's 8-step gate pattern.
  @impl true
  def handle_event("toggle_stem_loop_step", %{"deck" => deck_str, "loop_id" => loop_id, "step" => step_str}, socket) do
    deck_number = String.to_integer(deck_str)
    stem_loops_key = stem_loops_assign_key(deck_number)
    step = String.to_integer(step_str)

    case DJ.get_stem_loop(loop_id) do
      %DJ.StemLoop{} = stem_loop ->
        current_steps = stem_loop.steps || List.duplicate(true, 8)
        updated_steps = List.update_at(current_steps, step, &(!&1))

        case DJ.update_stem_loop(stem_loop, %{steps: updated_steps}) do
          {:ok, _} ->
            updated_loops =
              socket.assigns
              |> Map.get(stem_loops_key, [])
              |> Enum.map(fn l -> if l.id == loop_id, do: %{l | steps: updated_steps}, else: l end)

            {:noreply, assign(socket, stem_loops_key, updated_loops)}

          {:error, _} ->
            {:noreply, socket}
        end

      nil ->
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

  def handle_event("toggle_browser", _params, socket) do
    {:noreply, assign(socket, :browser_open, !socket.assigns.browser_open)}
  end

  def handle_event("browser_search", %{"value" => q}, socket) do
    {:noreply, assign(socket, :browser_search, q)}
  end

  # -- Template --

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="dj-tab-root"
      phx-target={@myself}
    >
      <div
        id="dj-tab"
        phx-hook="DjDeck"
        class="p-4 md:p-6 pb-10"
      >
      <div class="w-full max-w-7xl mx-auto overflow-x-hidden">
        <%!-- Track Browser Toggle --%>
        <div class="flex items-center mb-4">
          <button
            phx-click="toggle_browser"
            phx-target={@myself}
            class={"flex items-center gap-2 px-4 py-2 text-sm rounded-lg font-medium transition-colors " <>
              if(@browser_open,
                do: "bg-cyan-700 text-white",
                else: "bg-gray-800 text-gray-300 hover:bg-gray-700 hover:text-white"
              )}
          >
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 10h16M4 14h16M4 18h16" />
            </svg>
            Library Browser
          </button>
        </div>

        <%!-- Track Browser Panel --%>
        <div :if={@browser_open} class="mb-4 bg-gray-900 rounded-xl border border-cyan-700/30 overflow-hidden">
          <div class="px-4 py-3 border-b border-gray-700/50">
            <input
              type="text"
              value={@browser_search}
              phx-keyup="browser_search"
              phx-target={@myself}
              name="value"
              placeholder="Search tracks..."
              class="w-full px-3 py-2 bg-gray-800 border border-gray-600 rounded-lg text-sm text-gray-200 placeholder-gray-500 focus:outline-none focus:ring-1 focus:ring-cyan-500"
            />
          </div>
          <div class="overflow-y-auto max-h-52">
            <%= for track <- Enum.filter(@tracks, fn t ->
              q = String.downcase(@browser_search)
              q == "" || String.contains?(String.downcase(t.title || ""), q) || String.contains?(String.downcase(t.artist || ""), q)
            end) do %>
              <div
                phx-click="load_track"
                phx-value-track-id={track.id}
                phx-value-deck="1"
                phx-target={@myself}
                class="flex items-center gap-3 px-4 py-2.5 hover:bg-gray-800/70 cursor-pointer border-b border-gray-800/50 last:border-0 transition-colors"
              >
                <div class="flex-1 min-w-0">
                  <p class="text-sm text-gray-200 font-medium truncate">{track.title}</p>
                  <p class="text-xs text-gray-500 truncate">{track.artist}</p>
                </div>
                <div :if={track.duration} class="text-xs text-gray-600 flex-shrink-0">
                  {div(track.duration, 60)}:{String.pad_leading(Integer.to_string(rem(track.duration, 60)), 2, "0")}
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Master Volume Strip (top center) --%>
        <div class="flex justify-center pb-3 mb-1">
          <div class="flex flex-col items-center gap-1">
            <span class="text-[9px] text-purple-400 font-bold uppercase tracking-widest">MASTER</span>
            <form phx-change="set_master_volume" phx-target={@myself}>
              <.dial_knob
                id="master-vol-knob"
                name="value"
                min={0}
                max={100}
                step={1}
                value={@master_volume}
                size={40}
              />
            </form>
            <span class="text-[9px] text-gray-500 font-mono">{@master_volume}%</span>
          </div>
        </div>

        <%!-- Main Decks (A/B) + Inline EQ columns --%>
        <div class="flex flex-row gap-0 items-start">
          <%!-- DECK 1 (A) --%>
          <div class="flex-1 min-w-0">
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
              show_eq={false}
              grid_mode={@deck_1_grid_mode}
              grid_fraction={@deck_1_grid_fraction}
              leading_stem={@deck_1_leading_stem}
              rhythmic_quantize={@deck_1_rhythmic_quantize}
              midi_learn_mode={@dj_midi_learn_mode}
              midi_learn_target={@dj_midi_learn_target}
              deck_type={@deck_1_deck_type}
              is_master={@master_deck_number == 1}
              key_lock={@deck_1_key_lock}
              chef_type={@deck_1_chef_type}
              cue_sort={@deck_1_cue_sort}
              cue_page={@deck_1_cue_page}
              cue_per_page={@deck_1_cue_per_page}
              chef_sets={@deck_1_chef_sets}
            />
          </div>

          <%!-- Center Mixer Column: EQ + Pitch + Stems + Volume Faders + Crossfader --%>
          <%!-- Structured as: [D1 col | D2 col] side by side, crossfader full-width below --%>
          <div class="flex-shrink-0 flex flex-col border-x border-gray-800/60">
            <%!-- D1 + D2 side by side --%>
            <div class="flex">
              <%!-- Deck A (D1) column --%>
              <div class="flex flex-col items-center gap-1 pt-2 px-2 border-r border-gray-800/40 min-w-[60px]">
                <span class="text-[9px] text-cyan-500 font-bold uppercase tracking-widest">A</span>
                <%!-- EQ Knobs --%>
                <%= for {band, label} <- [{"high", "HI"}, {"mid", "MID"}, {"low", "LO"}] do %>
                  <form phx-change={"set_eq_gain_deck_1_" <> band} phx-target={@myself}>
                    <input type="hidden" name="deck" value="1" />
                    <input type="hidden" name="band" value={band} />
                    <.dial_knob id={"d1-eq-" <> band} name="gain"
                      min={-12} max={12} step={1} value={0} size={32} label={label} />
                  </form>
                <% end %>
                <%!-- Pitch Knob --%>
                <div class="flex flex-col items-center gap-0.5 mt-1">
                  <span class={"text-[7px] font-mono font-bold " <>
                    cond do
                      @deck_1.pitch_adjust > 0 -> "text-green-400"
                      @deck_1.pitch_adjust < 0 -> "text-red-400"
                      true -> "text-gray-600"
                    end}>
                    {format_pitch(@deck_1.pitch_adjust)}
                  </span>
                  <form phx-change="set_pitch" phx-target={@myself} phx-value-deck="1">
                    <.dial_knob id="d1-pitch" name="value"
                      min={-80} max={80} step={1}
                      value={trunc(@deck_1.pitch_adjust * 10)}
                      size={32} label="PITCH" />
                  </form>
                  <button phx-click="pitch_reset" phx-target={@myself} phx-value-deck="1"
                    disabled={@deck_1.pitch_adjust == 0.0}
                    class={"px-1 py-0.5 text-[7px] font-bold rounded transition-colors " <>
                      if(@deck_1.pitch_adjust == 0.0,
                        do: "bg-gray-800 text-gray-700 cursor-not-allowed",
                        else: "bg-gray-700 text-gray-400 hover:bg-gray-600"
                      )}>RST</button>
                </div>
                <%!-- Stem M/S for Deck A --%>
                <% d1_stems = Enum.map(@deck_1.stems || [], &Atom.to_string(&1.stem_type)) %>
                <div :if={length(d1_stems) > 0} class="flex flex-col gap-0.5 mt-1 w-full">
                  <%= for stem_type <- d1_stems do %>
                    <% state = Map.get(@deck_1.stem_states, stem_type, "on") %>
                    <div class="flex items-center gap-0.5 w-full">
                      <button phx-click="toggle_stem_state" phx-target={@myself}
                        phx-value-deck="1" phx-value-stem={stem_type} phx-value-mode="solo"
                        class={"w-4 h-4 text-[7px] font-bold rounded transition-colors " <>
                          if(state == "solo", do: "bg-yellow-500 text-black", else: "bg-gray-700 text-gray-600 hover:bg-gray-600")}
                        title={"Solo #{stem_type} (A)"}>S</button>
                      <div class={"flex-1 text-[7px] font-bold text-center py-0.5 rounded truncate " <>
                        case state do
                          "mute" -> "bg-gray-800 text-gray-600 line-through"
                          "solo" -> "bg-yellow-900/20 text-yellow-400"
                          _ -> "bg-gray-800/40 text-gray-400"
                        end}
                        style={"background-color: #{if state == "on", do: stem_color_hex(stem_type) <> "22", else: ""}"}
                      >{String.slice(stem_type, 0, 3)}</div>
                      <button phx-click="toggle_stem_state" phx-target={@myself}
                        phx-value-deck="1" phx-value-stem={stem_type} phx-value-mode="mute"
                        class={"w-4 h-4 text-[7px] font-bold rounded transition-colors " <>
                          if(state == "mute", do: "bg-red-700 text-white", else: "bg-gray-700 text-gray-600 hover:bg-gray-600")}
                        title={"Mute #{stem_type} (A)"}>M</button>
                    </div>
                  <% end %>
                </div>
                <%!-- Deck A Volume Fader (vertical) --%>
                <div class="flex flex-col items-center gap-0.5 mt-2 pt-2 border-t border-gray-700/30 w-full">
                  <span class="text-[7px] text-gray-600 uppercase">VOL</span>
                  <form phx-change="set_deck_volume" phx-target={@myself} phx-value-deck="1">
                    <div class="relative flex items-center justify-center" style="height: 80px; width: 20px;">
                      <%!-- Track --%>
                      <div class="absolute w-1.5 rounded-full bg-gray-700" style="top: 2px; bottom: 2px;"></div>
                      <%!-- Fill --%>
                      <div class="absolute w-1.5 rounded-full bg-cyan-600/50"
                        style={"bottom: 2px; height: #{@deck_1_volume * 0.76}px;"}></div>
                      <input type="range" name="level" min="0" max="100" value={@deck_1_volume}
                        class="absolute cursor-pointer appearance-none bg-transparent accent-cyan-500"
                        style="writing-mode: vertical-lr; direction: rtl; width: 80px; height: 20px;
                          transform: rotate(90deg); transform-origin: center;"
                        aria-label="Deck A volume" />
                      <%!-- Cap indicator --%>
                      <div class="absolute w-4 h-3 bg-gray-200 rounded-sm shadow border border-gray-400 pointer-events-none"
                        style={"bottom: #{2 + @deck_1_volume * 0.76 - 6}px;"}>
                      </div>
                    </div>
                  </form>
                  <span class="text-[7px] text-cyan-500 font-mono">{@deck_1_volume}</span>
                </div>
              </div>

              <%!-- Deck B (D2) column --%>
              <div class="flex flex-col items-center gap-1 pt-2 px-2 min-w-[60px]">
                <span class="text-[9px] text-orange-500 font-bold uppercase tracking-widest">B</span>
                <%!-- EQ Knobs --%>
                <%= for {band, label} <- [{"high", "HI"}, {"mid", "MID"}, {"low", "LO"}] do %>
                  <form phx-change={"set_eq_gain_deck_2_" <> band} phx-target={@myself}>
                    <input type="hidden" name="deck" value="2" />
                    <input type="hidden" name="band" value={band} />
                    <.dial_knob id={"d2-eq-" <> band} name="gain"
                      min={-12} max={12} step={1} value={0} size={32} label={label} />
                  </form>
                <% end %>
                <%!-- Pitch Knob --%>
                <div class="flex flex-col items-center gap-0.5 mt-1">
                  <span class={"text-[7px] font-mono font-bold " <>
                    cond do
                      @deck_2.pitch_adjust > 0 -> "text-green-400"
                      @deck_2.pitch_adjust < 0 -> "text-red-400"
                      true -> "text-gray-600"
                    end}>
                    {format_pitch(@deck_2.pitch_adjust)}
                  </span>
                  <form phx-change="set_pitch" phx-target={@myself} phx-value-deck="2">
                    <.dial_knob id="d2-pitch" name="value"
                      min={-80} max={80} step={1}
                      value={trunc(@deck_2.pitch_adjust * 10)}
                      size={32} label="PITCH" />
                  </form>
                  <button phx-click="pitch_reset" phx-target={@myself} phx-value-deck="2"
                    disabled={@deck_2.pitch_adjust == 0.0}
                    class={"px-1 py-0.5 text-[7px] font-bold rounded transition-colors " <>
                      if(@deck_2.pitch_adjust == 0.0,
                        do: "bg-gray-800 text-gray-700 cursor-not-allowed",
                        else: "bg-gray-700 text-gray-400 hover:bg-gray-600"
                      )}>RST</button>
                </div>
                <%!-- Stem M/S for Deck B --%>
                <% d2_stems = Enum.map(@deck_2.stems || [], &Atom.to_string(&1.stem_type)) %>
                <div :if={length(d2_stems) > 0} class="flex flex-col gap-0.5 mt-1 w-full">
                  <%= for stem_type <- d2_stems do %>
                    <% state = Map.get(@deck_2.stem_states, stem_type, "on") %>
                    <div class="flex items-center gap-0.5 w-full">
                      <button phx-click="toggle_stem_state" phx-target={@myself}
                        phx-value-deck="2" phx-value-stem={stem_type} phx-value-mode="solo"
                        class={"w-4 h-4 text-[7px] font-bold rounded transition-colors " <>
                          if(state == "solo", do: "bg-yellow-500 text-black", else: "bg-gray-700 text-gray-600 hover:bg-gray-600")}
                        title={"Solo #{stem_type} (B)"}>S</button>
                      <div class={"flex-1 text-[7px] font-bold text-center py-0.5 rounded truncate " <>
                        case state do
                          "mute" -> "bg-gray-800 text-gray-600 line-through"
                          "solo" -> "bg-yellow-900/20 text-yellow-400"
                          _ -> "bg-gray-800/40 text-gray-400"
                        end}
                        style={"background-color: #{if state == "on", do: stem_color_hex(stem_type) <> "22", else: ""}"}
                      >{String.slice(stem_type, 0, 3)}</div>
                      <button phx-click="toggle_stem_state" phx-target={@myself}
                        phx-value-deck="2" phx-value-stem={stem_type} phx-value-mode="mute"
                        class={"w-4 h-4 text-[7px] font-bold rounded transition-colors " <>
                          if(state == "mute", do: "bg-red-700 text-white", else: "bg-gray-700 text-gray-600 hover:bg-gray-600")}
                        title={"Mute #{stem_type} (B)"}>M</button>
                    </div>
                  <% end %>
                </div>
                <%!-- Deck B Volume Fader (vertical) --%>
                <div class="flex flex-col items-center gap-0.5 mt-2 pt-2 border-t border-gray-700/30 w-full">
                  <span class="text-[7px] text-gray-600 uppercase">VOL</span>
                  <form phx-change="set_deck_volume" phx-target={@myself} phx-value-deck="2">
                    <div class="relative flex items-center justify-center" style="height: 80px; width: 20px;">
                      <div class="absolute w-1.5 rounded-full bg-gray-700" style="top: 2px; bottom: 2px;"></div>
                      <div class="absolute w-1.5 rounded-full bg-orange-600/50"
                        style={"bottom: 2px; height: #{@deck_2_volume * 0.76}px;"}></div>
                      <input type="range" name="level" min="0" max="100" value={@deck_2_volume}
                        class="absolute cursor-pointer appearance-none bg-transparent accent-orange-500"
                        style="writing-mode: vertical-lr; direction: rtl; width: 80px; height: 20px;
                          transform: rotate(90deg); transform-origin: center;"
                        aria-label="Deck B volume" />
                      <div class="absolute w-4 h-3 bg-gray-200 rounded-sm shadow border border-gray-400 pointer-events-none"
                        style={"bottom: #{2 + @deck_2_volume * 0.76 - 6}px;"}>
                      </div>
                    </div>
                  </form>
                  <span class="text-[7px] text-orange-500 font-mono">{@deck_2_volume}</span>
                </div>
              </div>
            </div>

            <%!-- Crossfader (full width of center block, below volume faders) --%>
            <div class="flex flex-col items-center gap-1 px-2 pt-2 pb-2 border-t border-gray-700/40 mt-1">
              <div class="flex items-center gap-2 w-full justify-center mb-0.5">
                <span class="text-[8px] text-gray-500 uppercase tracking-widest">XFADER</span>
                <button
                  phx-click="toggle_crossfader_split"
                  phx-target={@myself}
                  class={"px-1 py-0.5 text-[7px] font-bold rounded transition-colors " <>
                    if(@crossfader_split,
                      do: "bg-amber-600/80 text-white ring-1 ring-amber-400/50",
                      else: "bg-gray-700 text-gray-500 hover:bg-gray-600"
                    )}
                  title="Split crossfader: A/C ↔ B/D"
                >SPLIT</button>
              </div>
              <form phx-change="crossfader" phx-target={@myself} class="w-full">
                <div class="relative flex items-center w-full" style="min-width: 100px;">
                  <span class="text-[8px] text-cyan-500 mr-1">A</span>
                  <div class="relative flex-1 flex items-center h-6">
                    <%!-- Fader track --%>
                    <div class="absolute inset-x-0 my-auto h-2 bg-gray-700 rounded-full overflow-hidden">
                      <div class="absolute inset-y-0 bg-gradient-to-r from-cyan-600/40 to-orange-600/40 rounded-full w-full opacity-60"></div>
                    </div>
                    <%!-- Fader cap (positioned by value) --%>
                    <div class="absolute w-4 h-6 bg-gray-300 rounded shadow-md border border-gray-400 pointer-events-none"
                      style={"left: calc(#{((@crossfader + 100) / 200) * 100}% - 8px);"}>
                    </div>
                    <input type="range" name="value"
                      min="-100" max="100" step="1" value={@crossfader}
                      class="absolute inset-0 w-full opacity-0 cursor-pointer h-6"
                      aria-label="Crossfader" />
                  </div>
                  <span class="text-[8px] text-orange-500 ml-1">B</span>
                </div>
              </form>
              <div class="flex justify-between w-full mt-0.5">
                <span class="text-[7px] text-gray-600">A{if @crossfader_split, do: "/C", else: ""}</span>
                <span class="text-[8px] text-gray-500 font-mono">{@crossfader}</span>
                <span class="text-[7px] text-gray-600">B{if @crossfader_split, do: "/D", else: ""}</span>
              </div>
            </div>
          </div>

          <%!-- DECK 2 (B) --%>
          <div class="flex-1 min-w-0">
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
              show_eq={false}
              grid_mode={@deck_2_grid_mode}
              grid_fraction={@deck_2_grid_fraction}
              leading_stem={@deck_2_leading_stem}
              rhythmic_quantize={@deck_2_rhythmic_quantize}
              midi_learn_mode={@dj_midi_learn_mode}
              midi_learn_target={@dj_midi_learn_target}
              deck_type={@deck_2_deck_type}
              is_master={@master_deck_number == 2}
              key_lock={@deck_2_key_lock}
              chef_type={@deck_2_chef_type}
              cue_sort={@deck_2_cue_sort}
              cue_page={@deck_2_cue_page}
              cue_per_page={@deck_2_cue_per_page}
              chef_sets={@deck_2_chef_sets}
            />
          </div>
        </div>

        <%!-- Loop Track Decks (C/D) - Simplified loop-focused decks --%>
        <div class="mt-4 grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="flex items-center gap-2 col-span-full mb-1">
            <span class="text-xs text-gray-500 uppercase tracking-widest font-semibold">Loop Tracks</span>
            <div class="flex-1 h-px bg-gray-700/50"></div>
          </div>
          <.loop_deck_panel
            deck_number={3}
            deck={@deck_3}
            tracks={@tracks}
            volume={@deck_3_volume}
            cue_points={@deck_3_cue_points}
            deck_type={@deck_3_deck_type}
            loop_pads={@deck_3_loop_pads}
            pad_mode={@deck_3_pad_mode}
            poly_voices={@deck_3_poly_voices}
            pad_fade={@deck_3_pad_fade}
            active_pads={@deck_3_active_pads}
            alchemy_sets={@alchemy_sets}
            myself={@myself}
          />
          <.loop_deck_panel
            deck_number={4}
            deck={@deck_4}
            tracks={@tracks}
            volume={@deck_4_volume}
            cue_points={@deck_4_cue_points}
            deck_type={@deck_4_deck_type}
            loop_pads={@deck_4_loop_pads}
            pad_mode={@deck_4_pad_mode}
            poly_voices={@deck_4_poly_voices}
            pad_fade={@deck_4_pad_fade}
            active_pads={@deck_4_active_pads}
            alchemy_sets={@alchemy_sets}
            myself={@myself}
          />
        </div>

        <%!-- Crossfader Curve + Master Sync (compact, below center strip) --%>
        <div class="mt-4 bg-gray-900 rounded-xl p-3">
          <div class="flex items-center flex-wrap gap-3 justify-between">
            <div class="flex items-center gap-2">
              <span class="text-xs text-gray-500 uppercase tracking-wider">Curve</span>
              <button
                :for={curve <- [{"linear", "Lin"}, {"equal_power", "EQ-P"}, {"sharp", "Sharp"}]}
                phx-click="set_crossfader_curve"
                phx-target={@myself}
                phx-value-curve={elem(curve, 0)}
                class={"px-2 py-1 text-xs rounded font-medium transition-colors " <>
                  if(@crossfader_curve == elem(curve, 0),
                    do: "bg-purple-600 text-white",
                    else: "bg-gray-700 text-gray-400 hover:bg-gray-600"
                  )}
              >
                {elem(curve, 1)}
              </button>
            </div>
            <span class="text-xs text-gray-600 hidden md:inline">Z / X to nudge crossfader</span>
            <button
              phx-click="master_sync"
              phx-target={@myself}
              disabled={is_nil(@deck_1.track) || is_nil(@deck_2.track) || @deck_1.tempo_bpm <= 0 || @deck_2.tempo_bpm <= 0}
              class={"px-4 py-1.5 text-xs font-bold rounded-lg transition-colors " <>
                if(is_nil(@deck_1.track) || is_nil(@deck_2.track) || @deck_1.tempo_bpm <= 0 || @deck_2.tempo_bpm <= 0,
                  do: "bg-gray-700 text-gray-600 cursor-not-allowed",
                  else: "bg-yellow-600 text-white hover:bg-yellow-500 ring-1 ring-yellow-400/30"
                )}
            >
              MASTER SYNC
            </button>
          </div>
        </div>

        <%!-- Metronome --%>
        <div class="mt-4 bg-gray-900 rounded-xl p-4 flex items-center gap-4">
          <span class="text-xs text-gray-500 uppercase tracking-wider font-semibold">Metronome</span>
          <button
            phx-click="toggle_metronome"
            phx-target={@myself}
            class={"px-4 py-2 text-sm font-bold rounded-lg transition-colors " <>
              if(@metronome_active,
                do: "bg-green-600 text-white ring-1 ring-green-400/30 animate-pulse",
                else: "bg-gray-700 text-gray-300 hover:bg-gray-600"
              )}
          >
            {if @metronome_active, do: "◉ CLICK ON", else: "◎ CLICK OFF"}
          </button>
          <div class="flex items-center gap-2 flex-1">
            <span class="text-[10px] text-gray-600">Vol</span>
            <form phx-change="set_metronome_volume" phx-target={@myself} class="flex-1">
              <input type="range" name="volume" min="0" max="100" value={@metronome_volume}
                class="w-full h-1.5 rounded appearance-none cursor-pointer accent-green-500" />
            </form>
            <span class="text-[10px] text-gray-500 w-8 text-right">{@metronome_volume}%</span>
          </div>
          <span class="text-xs text-gray-500 font-mono">
            {if @deck_1.tempo_bpm > 0, do: "#{Float.round(@deck_1.tempo_bpm, 1)} BPM", else: "—"}
          </span>
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

        <%!-- Saved Presets Panel (US-009/010/011) --%>
        <div class="mt-4 bg-gray-900 rounded-xl border border-indigo-700/30">
          <button
            phx-click="toggle_presets_panel"
            phx-target={@myself}
            class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-indigo-300 hover:text-indigo-200 transition-colors"
          >
            <span class="flex items-center gap-2">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
              </svg>
              Presets
              <span :if={length(@saved_presets) > 0} class="text-xs bg-indigo-700/40 text-indigo-300 px-1.5 py-0.5 rounded-full">
                {length(@saved_presets)}
              </span>
            </span>
            <div class="flex items-center gap-2">
              <button
                phx-click="export_preset"
                phx-target={@myself}
                type="button"
                class="text-xs bg-gray-700 hover:bg-gray-600 text-gray-300 px-2 py-1 rounded transition-colors"
              >
                Export JSON
              </button>
              <svg
                class={"w-4 h-4 transition-transform " <> if(@presets_panel_open, do: "rotate-180", else: "")}
                fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
              </svg>
            </div>
          </button>

          <div :if={@presets_panel_open} class="px-4 pb-4 border-t border-indigo-700/20">
            <%!-- Save Current Layout Form --%>
            <div class="mt-3 flex items-center gap-2">
              <form phx-change="preset_name_change" phx-submit="save_preset" phx-target={@myself} class="flex-1 flex gap-2">
                <input
                  type="text"
                  name="value"
                  value={@preset_name_input}
                  placeholder="Layout name..."
                  class="flex-1 px-3 py-1.5 bg-gray-800 border border-gray-600 rounded-lg text-sm text-gray-200 placeholder-gray-500 focus:outline-none focus:ring-1 focus:ring-indigo-500/50"
                />
                <button
                  type="submit"
                  disabled={String.trim(@preset_name_input) == ""}
                  class={"px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors " <>
                    if(String.trim(@preset_name_input) == "",
                      do: "bg-gray-700 text-gray-500 cursor-not-allowed",
                      else: "bg-indigo-600 text-white hover:bg-indigo-500"
                    )}
                >
                  Save Layout
                </button>
              </form>
            </div>

            <%!-- Saved Presets List --%>
            <div :if={@saved_presets == []} class="mt-3 text-xs text-gray-600 text-center py-2">
              No saved presets yet
            </div>
            <div :if={@saved_presets != []} class="mt-3 flex flex-col gap-1.5 max-h-48 overflow-y-auto">
              <div
                :for={preset <- @saved_presets}
                class="flex items-center gap-2 px-3 py-2 bg-gray-800/60 rounded-lg border border-gray-700/30 hover:border-indigo-700/30 transition-colors"
              >
                <div class="flex-1 min-w-0">
                  <p class="text-sm text-gray-200 font-medium truncate">{preset.name}</p>
                  <div class="flex items-center gap-1.5 mt-0.5">
                    <span class={"text-[10px] px-1.5 py-0.5 rounded font-medium " <>
                      case preset.source do
                        "tsi" -> "bg-blue-700/40 text-blue-300"
                        "touchosc" -> "bg-teal-700/40 text-teal-300"
                        "rekordbox" -> "bg-red-700/40 text-red-300"
                        _ -> "bg-gray-700/60 text-gray-400"
                      end}>
                      {preset.source}
                    </span>
                  </div>
                </div>
                <button
                  phx-click="load_preset"
                  phx-target={@myself}
                  phx-value-id={preset.id}
                  type="button"
                  class="text-xs bg-indigo-700/50 hover:bg-indigo-700 text-indigo-200 px-2 py-1 rounded transition-colors flex-shrink-0"
                >
                  Load
                </button>
                <button
                  phx-click="delete_preset"
                  phx-target={@myself}
                  phx-value-id={preset.id}
                  type="button"
                  class="text-xs text-gray-600 hover:text-red-400 transition-colors flex-shrink-0"
                >
                  <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>

            <%!-- Import MIDI Preset Section --%>
            <div class="mt-4 pt-3 border-t border-gray-700/30">
              <p class="text-xs text-gray-500 mb-2 font-semibold uppercase tracking-wider">Import MIDI Preset</p>
              <form phx-submit="upload_preset" phx-change="validate_preset" phx-target={@myself}>
                <div class="flex items-center gap-2">
                  <div class="flex-1">
                    <.live_file_input upload={@uploads.preset_file} class="
                      block w-full text-xs text-gray-400
                      file:mr-3 file:py-1.5 file:px-3
                      file:rounded file:border-0
                      file:text-xs file:font-semibold
                      file:bg-purple-700 file:text-white
                      hover:file:bg-purple-600 file:cursor-pointer
                    " />
                  </div>
                  <button
                    type="submit"
                    class="px-3 py-1.5 bg-purple-700 text-white text-xs font-medium rounded hover:bg-purple-600 transition-colors disabled:bg-gray-700 disabled:text-gray-500"
                    disabled={@uploads.preset_file.entries == []}
                  >
                    Import
                  </button>
                </div>
                <div :for={entry <- @uploads.preset_file.entries} class="mt-1">
                  <div :for={err <- upload_errors(@uploads.preset_file, entry)} class="text-xs text-red-400">
                    {upload_error_to_string(err)}
                  </div>
                </div>
              </form>
            </div>

            <%!-- Rekordbox XML Import Section (US-010) --%>
            <div class="mt-3 pt-3 border-t border-gray-700/30">
              <p class="text-xs text-gray-500 mb-2 font-semibold uppercase tracking-wider">Import Rekordbox</p>
              <form phx-submit="import_rekordbox" phx-change="validate_rekordbox" phx-target={@myself}>
                <div class="flex items-center gap-2">
                  <div class="flex-1">
                    <.live_file_input upload={@uploads.rekordbox_file} class="
                      block w-full text-xs text-gray-400
                      file:mr-3 file:py-1.5 file:px-3
                      file:rounded file:border-0
                      file:text-xs file:font-semibold
                      file:bg-red-800 file:text-white
                      hover:file:bg-red-700 file:cursor-pointer
                    " />
                  </div>
                  <button
                    type="submit"
                    class="px-3 py-1.5 bg-red-800 text-white text-xs font-medium rounded hover:bg-red-700 transition-colors disabled:bg-gray-700 disabled:text-gray-500"
                    disabled={@uploads.rekordbox_file.entries == []}
                  >
                    Import
                  </button>
                </div>
                <div :for={entry <- @uploads.rekordbox_file.entries} class="mt-1">
                  <div :for={err <- upload_errors(@uploads.rekordbox_file, entry)} class="text-xs text-red-400">
                    {upload_error_to_string(err)}
                  </div>
                </div>
              </form>
              <div :if={@rekordbox_import_result} class="mt-2 text-xs text-green-400 bg-green-900/20 rounded px-2 py-1.5 border border-green-700/30">
                Imported {@rekordbox_import_result.cues_created} cues from
                {@rekordbox_import_result.matched_tracks}/{@rekordbox_import_result.total_tracks} tracks
              </div>
            </div>
          </div>
        </div>

      </div>

      <%!-- Import Preset Section (legacy toggle, kept for keyboard shortcut compat) --%>
      <div class="hidden">
        <button phx-click="toggle_preset_section" phx-target={@myself}></button>
      </div>

      <%!-- Virtual Controller --%>
      <.live_component
        module={SoundForgeWeb.Live.Components.VirtualController}
        id="virtual-controller"
        deck_1_cue_points={@deck_1_cue_points}
        deck_2_cue_points={@deck_2_cue_points}
      />

      <%!-- SMPTE + MIDI Clock Status Bar --%>
      <% d1_bar_beat = position_to_bar_beat(@deck_1.position, @deck_1.tempo_bpm) %>
      <% d2_bar_beat = position_to_bar_beat(@deck_2.position, @deck_2.tempo_bpm) %>
      <% midi_sync_active = @deck_1.midi_sync || @deck_2.midi_sync %>
      <div class="fixed bottom-0 left-0 right-0 z-50 bg-gray-950/95 backdrop-blur-sm border-t border-gray-700/50 px-3 py-1.5">
        <div class="max-w-7xl mx-auto flex items-center justify-between gap-2">
          <%!-- Deck 1 info --%>
          <div class="flex items-center gap-2 min-w-0">
            <span class="text-[10px] font-mono font-bold text-cyan-400 uppercase tracking-widest flex-shrink-0">DECK A</span>
            <span class="text-[10px] font-mono text-gray-300 truncate max-w-[120px]">
              {if @deck_1.track, do: @deck_1.track.title, else: "No Track"}
            </span>
            <span class="text-[10px] font-mono text-cyan-500/80 flex-shrink-0">
              {if @deck_1.tempo_bpm > 0, do: "#{Float.round(@deck_1.tempo_bpm * 1.0, 1)} BPM", else: "--"}
            </span>
            <%!-- SMPTE timecode --%>
            <span class="text-[10px] font-mono text-gray-400 flex-shrink-0 tabular-nums">
              {Timecode.ms_to_smpte(trunc(@deck_1.position * 1000))}
            </span>
            <%!-- BAR.BEAT.TK --%>
            <span class="text-[10px] font-mono text-cyan-600/80 flex-shrink-0 tabular-nums hidden md:block"
              title="Bar.Beat.Tick (4/4)">
              {d1_bar_beat}
            </span>
            <%= if @deck_1.midi_sync do %>
              <span class="text-[9px] font-bold px-1 py-0.5 rounded bg-green-900/50 text-green-400 border border-green-700/40 flex-shrink-0">
                MIDI SYNC
              </span>
            <% end %>
          </div>

          <%!-- Center: clock source + mode indicators --%>
          <div class="flex items-center gap-2 flex-shrink-0">
            <div class="hidden md:flex items-center gap-1.5">
              <span class="text-[9px] font-mono text-yellow-400/50 tracking-[0.2em]">SMPTE</span>
              <span class="text-[9px] text-gray-600">·</span>
              <span class={"text-[9px] font-bold px-1.5 py-0.5 rounded flex-shrink-0 " <>
                if(midi_sync_active,
                  do: "bg-green-900/40 text-green-400 border border-green-700/30",
                  else: "bg-gray-800 text-gray-500 border border-gray-700/30")}>
                {if midi_sync_active, do: "EXT CLK", else: "INT CLK"}
              </span>
            </div>
            <%!-- Mode indicators: DJ / DAW / PADS --%>
            <div class="flex items-center gap-1">
              <span class="text-[9px] font-bold px-1.5 py-0.5 rounded bg-purple-900/50 text-purple-300 border border-purple-700/30">DJ</span>
              <span class="text-[9px] px-1.5 py-0.5 rounded bg-gray-800/50 text-gray-600 border border-gray-700/20">DAW</span>
              <span class="text-[9px] px-1.5 py-0.5 rounded bg-gray-800/50 text-gray-600 border border-gray-700/20">PADS</span>
            </div>
          </div>

          <%!-- Deck 2 info --%>
          <div class="flex items-center gap-2 min-w-0 justify-end">
            <%= if @deck_2.midi_sync do %>
              <span class="text-[9px] font-bold px-1 py-0.5 rounded bg-green-900/50 text-green-400 border border-green-700/40 flex-shrink-0">
                MIDI SYNC
              </span>
            <% end %>
            <%!-- BAR.BEAT.TK --%>
            <span class="text-[10px] font-mono text-orange-600/80 flex-shrink-0 tabular-nums hidden md:block"
              title="Bar.Beat.Tick (4/4)">
              {d2_bar_beat}
            </span>
            <%!-- SMPTE timecode --%>
            <span class="text-[10px] font-mono text-gray-400 flex-shrink-0 tabular-nums">
              {Timecode.ms_to_smpte(trunc(@deck_2.position * 1000))}
            </span>
            <span class="text-[10px] font-mono text-orange-500/80 flex-shrink-0">
              {if @deck_2.tempo_bpm > 0, do: "#{Float.round(@deck_2.tempo_bpm * 1.0, 1)} BPM", else: "--"}
            </span>
            <span class="text-[10px] font-mono text-gray-300 truncate max-w-[120px]">
              {if @deck_2.track, do: @deck_2.track.title, else: "No Track"}
            </span>
            <span class="text-[10px] font-mono font-bold text-orange-400 uppercase tracking-widest flex-shrink-0">DECK B</span>
          </div>
        </div>
      </div>
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
          <h4 class="text-xs font-bold text-cyan-400 uppercase tracking-wider mb-2">Deck A</h4>
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
          <h4 class="text-xs font-bold text-orange-400 uppercase tracking-wider mb-2">Deck B</h4>
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

  # -- Dial Knob (rotary control) --

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :min, :any, default: -12
  attr :max, :any, default: 12
  attr :step, :any, default: 1
  attr :value, :any, default: 0
  attr :size, :integer, default: 36
  attr :label, :string, default: nil

  defp dial_knob(assigns) do
    size = assigns.size
    half = div(size, 2)
    range = max(assigns.max - assigns.min, 1) * 1.0
    normalized = min(1.0, max(0.0, (assigns.value * 1.0 - assigns.min * 1.0) / range))
    rotation = -135.0 + 270.0 * normalized

    assigns =
      assigns
      |> assign(:half, half)
      |> assign(:indicator_height, half - 4)
      |> assign(:rotation, rotation)

    ~H"""
    <div id={@id} class="djknob flex flex-col items-center gap-0.5">
      <div
        class="relative rounded-full bg-gray-900 border border-gray-700 cursor-pointer"
        style={"width: #{@size}px; height: #{@size}px; box-shadow: inset 0 2px 4px rgba(0,0,0,0.7), 0 1px 0 rgba(255,255,255,0.04);"}
      >
        <div
          class="djknob-ind absolute rounded-full pointer-events-none"
          style={"background: rgba(255,255,255,0.85); width: 2px; height: #{@indicator_height}px; left: #{@half - 1}px; top: 4px; transform: rotate(#{@rotation}deg); transform-origin: center bottom;"}
        ></div>
        <input
          type="range"
          name={@name}
          min={@min}
          max={@max}
          step={@step}
          value={@value}
          tabindex="-1"
          class="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
          style="margin: 0; padding: 0;"
          oninput={"(function(i){var r=(-135+270*((i.value-i.min)/(i.max-i.min)));document.getElementById('#{@id}').querySelector('.djknob-ind').style.transform='rotate('+r+'deg)'})(this)"}
        />
      </div>
      <span :if={@label} class="text-[8px] text-gray-500 uppercase leading-none">{@label}</span>
    </div>
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
  attr :show_eq, :boolean, default: true
  attr :grid_mode, :string, default: "bar"
  attr :grid_fraction, :string, default: "1/4"
  attr :leading_stem, :string, default: "drums"
  attr :rhythmic_quantize, :boolean, default: false
  attr :midi_learn_mode, :boolean, default: false
  attr :midi_learn_target, :any, default: nil
  attr :deck_type, :string, default: "full"
  attr :is_master, :boolean, default: false
  attr :key_lock, :boolean, default: false
  attr :chef_type, :string, default: "hot_cue_set"
  attr :cue_sort, :string, default: "confidence"
  attr :cue_page, :integer, default: 1
  attr :cue_per_page, :integer, default: 8
  attr :chef_sets, :list, default: []

  defp deck_panel(assigns) do
    deck_color = if assigns.deck_number == 1, do: "cyan", else: "orange"
    assigns = assign(assigns, :deck_color, deck_color)

    ~H"""
    <div class={"bg-gray-900 rounded-xl p-4 border border-gray-700/50 " <>
      if(@deck.playing, do: "ring-1 ring-#{@deck_color}-500/30", else: "")}>
      <%!-- Deck Header: Label + Type Selector + Status + MASTER/SYNC/KEY --%>
      <div class="flex items-center justify-between mb-2 flex-wrap gap-1">
        <div class="flex items-center gap-2">
          <span class={"text-sm font-bold tracking-wider " <>
            if(@deck_number == 1, do: "text-cyan-400", else: "text-orange-400")}>
            DECK {deck_letter(@deck_number)}
          </span>
          <%!-- Deck Type Selector --%>
          <form phx-change="set_deck_type" phx-target={@myself}>
            <input type="hidden" name="deck" value={@deck_number} />
            <select name="deck_type"
              class="bg-gray-800 text-gray-400 text-[8px] rounded px-1 py-0.5 border border-gray-700/50 cursor-pointer"
              title="Deck type">
              <option value="full" selected={@deck_type == "full"}>FULL</option>
              <option value="loop" selected={@deck_type == "loop"}>LOOP</option>
              <option value="soundboard" selected={@deck_type == "soundboard"}>SND</option>
            </select>
          </form>
        </div>
        <div class="flex items-center gap-1">
          <%!-- MASTER button --%>
          <button
            phx-click="set_master_deck"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            class={"px-1.5 py-0.5 text-[8px] font-bold rounded transition-colors " <>
              if(@is_master,
                do: "bg-amber-500 text-black ring-1 ring-amber-300",
                else: "bg-gray-700 text-gray-500 hover:bg-gray-600"
              )}
            title="Designate this deck as master (sets tempo reference)"
          >
            MST
          </button>
          <%!-- SYNC button --%>
          <button
            phx-click="toggle_midi_sync"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            class={"px-1.5 py-0.5 text-[8px] font-bold rounded transition-colors " <>
              if(@midi_sync,
                do: "bg-green-600 text-white ring-1 ring-green-400/50",
                else: "bg-gray-700 text-gray-500 hover:bg-gray-600"
              )}
            title="Sync this deck's tempo to master"
          >
            SYNC
          </button>
          <%!-- KEY lock button --%>
          <button
            phx-click="toggle_key_lock"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            class={"px-1.5 py-0.5 text-[8px] font-bold rounded transition-colors " <>
              if(@key_lock,
                do: "bg-violet-600 text-white ring-1 ring-violet-400/50",
                else: "bg-gray-700 text-gray-500 hover:bg-gray-600"
              )}
            title="Key Lock: maintain musical key when tempo changes"
          >
            ♪
          </button>
          <span class={"text-[9px] px-1.5 py-0.5 rounded-full " <>
            if(@deck.playing, do: "bg-green-500/20 text-green-400", else: "bg-gray-700 text-gray-600")}>
            {if @deck.playing, do: "▶", else: "■"}
          </span>
        </div>
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

      <%!-- Grid Controls + Leading Stem + Rhythmic Quantize --%>
      <div class="flex items-center gap-2 mb-1.5 flex-wrap">
        <%!-- Grid Mode Dropdown --%>
        <div class="flex items-center gap-1">
          <span class="text-[9px] text-gray-600 uppercase tracking-wider">Grid</span>
          <form phx-change="set_grid_mode" phx-target={@myself}>
            <input type="hidden" name="deck" value={@deck_number} />
            <select
              name="mode"
              class="bg-gray-800 text-gray-300 text-[8px] rounded px-1 py-0.5 border border-gray-700/50 cursor-pointer"
              title="Grid overlay mode"
            >
              <%= for {val, lbl} <- [{"bar", "BAR"}, {"beat", "BEAT"}, {"sub", "SUB"}, {"smart", "SMART"}] do %>
                <option value={val} selected={@grid_mode == val}>{lbl}</option>
              <% end %>
            </select>
          </form>
          <%!-- Fraction/interval dropdown --%>
          <form phx-change="set_grid_fraction" phx-target={@myself}>
            <input type="hidden" name="deck" value={@deck_number} />
            <select
              name="fraction"
              class="bg-gray-800 text-gray-300 text-[8px] rounded px-1 py-0.5 border border-gray-700/50 cursor-pointer"
              title="Grid interval / fraction"
            >
              <%= for {val, lbl} <- [{"1/1", "1/1"}, {"1/2", "1/2"}, {"1/4", "1/4"}, {"1/8", "1/8"}, {"1/16", "1/16"}, {"1/32", "1/32"}] do %>
                <option value={val} selected={(@grid_fraction || "1/4") == val}>{lbl}</option>
              <% end %>
            </select>
          </form>
        </div>

        <%!-- Leading Stem Selector --%>
        <div class="flex items-center gap-1">
          <span class="text-[9px] text-gray-600 uppercase tracking-wider">Stem</span>
          <form phx-change="set_leading_stem" phx-target={@myself}>
            <input type="hidden" name="deck" value={@deck_number} />
            <select
              name="stem"
              class="bg-gray-800 text-gray-300 text-[8px] rounded px-1 py-0.5 border border-gray-700/50 cursor-pointer"
            >
              <%= for {val, lbl} <- [{"drums", "Drums"}, {"bass", "Bass"}, {"vocals", "Vocals"}, {"other", "Other"}, {"auto", "Auto"}] do %>
                <option value={val} selected={@leading_stem == val}>{lbl}</option>
              <% end %>
            </select>
          </form>
        </div>

        <%!-- Rhythmic Quantize --%>
        <button
          phx-click="toggle_rhythmic_quantize"
          phx-target={@myself}
          phx-value-deck={@deck_number}
          class={"px-1.5 py-0.5 text-[8px] font-bold rounded transition-colors " <>
            if(@rhythmic_quantize,
              do: "bg-purple-700 text-white ring-1 ring-purple-400/40",
              else: "bg-gray-800 text-gray-500 hover:bg-gray-700 hover:text-gray-300"
            )}
          title="Rhythmic Quantize: snap play start to next beat"
        >
          QUANT
        </button>
      </div>

      <%!-- SMPTE Grid Canvas (rendered by JS hook above the waveform) --%>
      <canvas
        id={"smpte-grid-deck-#{@deck_number}"}
        phx-update="ignore"
        class="w-full rounded-t border-x border-t border-gray-700/30 bg-gray-950/80"
        style="height: 28px; display: block;"
        data-deck={@deck_number}
        data-grid-mode={@grid_mode}
        data-grid-fraction={@grid_fraction}
        data-show-smpte="true"
      ></canvas>

      <%!-- WaveSurfer Waveform --%>
      <div class="relative mb-4">
        <div
          id={"waveform-deck-#{@deck_number}"}
          phx-update="ignore"
          class="rounded-b bg-gray-800 border border-gray-700/30 overflow-hidden"
          style="min-height: 110px;"
          data-deck={@deck_number}
        >
        </div>
        <div
          :if={is_nil(@deck.track)}
          class="absolute inset-0 flex items-center justify-center text-gray-600 text-sm"
        >
          Load a track to see waveform
        </div>
      </div>

      <%!-- Hot Cue Pads A-H (rekordbox / Traktor style) --%>
      <div class="mb-4 border border-gray-700/50 rounded-lg p-3">
        <div class="flex items-center justify-between mb-2">
          <span class="text-xs text-gray-500 uppercase tracking-wider font-semibold">Hot Cues</span>
          <span class="text-[10px] text-gray-600">Click empty pad to set · Click set pad to jump</span>
        </div>
        <%!-- A-H hot cue pads — 2×4 grid (ADR-004: Rekordbox/Traktor standard) --%>
        <% hot_cues = @cue_points |> Enum.filter(&(&1.cue_type == :hot && !&1.auto_generated)) |> Map.new(&{&1.label, &1}) %>
        <% cue_colors = %{"A" => "#ef4444","B" => "#3b82f6","C" => "#22c55e","D" => "#eab308","E" => "#8b5cf6","F" => "#06b6d4","G" => "#f97316","H" => "#e5e7eb"} %>
        <div class="grid grid-cols-4 gap-1.5">
          <%= for letter <- ~w(A B C D E F G H) do %>
            <% cue = Map.get(hot_cues, letter) %>
            <% base_color = Map.get(cue_colors, letter, "#6b7280") %>
            <div class="relative group/hc">
              <%= if cue do %>
                <button
                  phx-click={
                    JS.dispatch("dj:seek",
                      to: "#dj-tab",
                      detail: %{deck: @deck_number, position: cue.position_ms / 1000.0}
                    )
                    |> JS.push("set_hot_cue",
                      value: %{deck: to_string(@deck_number), letter: letter},
                      target: @myself
                    )
                  }
                  class="w-full h-12 rounded-md text-xs font-bold text-white transition-all hover:brightness-115 active:scale-95 shadow-md flex flex-col items-center justify-center gap-0.5"
                  style={"background-color: #{cue.color}; box-shadow: 0 0 8px #{cue.color}55;"}
                  title={"Hot Cue #{letter} · #{format_ms(cue.position_ms)} — click to jump"}
                >
                  <span class="font-mono font-black text-sm leading-none">{letter}</span>
                  <span class="text-[8px] opacity-80 leading-none">{format_ms(cue.position_ms)}</span>
                </button>
                <button
                  phx-click="clear_hot_cue"
                  phx-target={@myself}
                  phx-value-deck={@deck_number}
                  phx-value-letter={letter}
                  class="absolute -top-1 -right-1 opacity-0 group-hover/hc:opacity-100 w-4 h-4 flex items-center justify-center rounded-full bg-red-600 text-white text-[9px] font-bold transition-opacity shadow z-10"
                  title="Clear hot cue #{letter}"
                >
                  ×
                </button>
              <% else %>
                <button
                  phx-click="set_hot_cue"
                  phx-target={@myself}
                  phx-value-deck={@deck_number}
                  phx-value-letter={letter}
                  disabled={is_nil(@deck.track)}
                  class={"w-full h-12 rounded-md text-sm font-black transition-all flex items-center justify-center " <>
                    if(is_nil(@deck.track),
                      do: "cursor-not-allowed opacity-30",
                      else: "hover:opacity-60 active:scale-95"
                    )}
                  style={"background-color: #{base_color}22; border: 1px solid #{base_color}44; color: #{base_color}99;"}
                  title={"Set Hot Cue #{letter} at current position"}
                >
                  {letter}
                </button>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Chef Cue System --%>
        <%
          auto_cues = Enum.filter(@cue_points, & &1.auto_generated)
          sorted_cues = case @cue_sort do
            "position" -> Enum.sort_by(auto_cues, & &1.position_ms)
            "intelligent" -> Enum.sort_by(auto_cues, &{&1.sort_order || 999, -((&1.confidence || 0.0) * 100 |> trunc)})
            _ -> Enum.sort_by(auto_cues, & -(&1.confidence || 0.0))
          end
          total_cues = length(sorted_cues)
          total_pages = max(1, ceil(total_cues / @cue_per_page))
          page_cues = sorted_cues |> Enum.drop((@cue_page - 1) * @cue_per_page) |> Enum.take(@cue_per_page)
        %>
        <div class="mt-2 pt-2 border-t border-gray-700/30">
          <%!-- Chef header + controls --%>
          <div class="flex items-center justify-between mb-1.5 flex-wrap gap-1">
            <span class="flex items-center gap-1 text-[10px] text-amber-400 uppercase tracking-wider font-bold">
              <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 24 24">
                <path d="M12 2L9.19 8.63 2 9.24l5.46 4.73L5.82 21 12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2z" />
              </svg>
              Chef
              <span :if={total_cues > 0} class="text-gray-500 font-normal normal-case">
                ({total_cues})
              </span>
            </span>
            <div class="flex items-center gap-1 flex-wrap">
              <%!-- Chef type dropdown --%>
              <form phx-change="set_chef_type" phx-target={@myself}>
                <input type="hidden" name="deck" value={@deck_number} />
                <select name="chef_type"
                  class="bg-gray-800 text-gray-400 text-[8px] rounded px-1 py-0.5 border border-gray-700/50 cursor-pointer">
                  <option value="cue_set" selected={@chef_type == "cue_set"}>Cue Set</option>
                  <option value="loop_set" selected={@chef_type == "loop_set"}>Loop Set</option>
                  <option value="hot_cue_set" selected={@chef_type == "hot_cue_set"}>Hot Cues</option>
                </select>
              </form>
              <%!-- Sort dropdown --%>
              <form phx-change="set_cue_sort" phx-target={@myself}>
                <input type="hidden" name="deck" value={@deck_number} />
                <select name="sort"
                  class="bg-gray-800 text-gray-400 text-[8px] rounded px-1 py-0.5 border border-gray-700/50 cursor-pointer">
                  <option value="confidence" selected={@cue_sort == "confidence"}>Confidence</option>
                  <option value="position" selected={@cue_sort == "position"}>Position</option>
                  <option value="intelligent" selected={@cue_sort == "intelligent"}>Intelligent</option>
                </select>
              </form>
              <%!-- Generate / Regen button --%>
              <%= if @detecting_cues do %>
                <svg class="w-3 h-3 animate-spin text-amber-400" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
              <% else %>
                <button
                  :if={@deck.track}
                  phx-click="generate_chef_set"
                  phx-target={@myself}
                  phx-value-deck={@deck_number}
                  phx-value-chef_type={@chef_type}
                  class={"px-1.5 py-0.5 text-[9px] font-bold rounded transition-colors " <>
                    if(total_cues > 0,
                      do: "bg-gray-700 text-gray-500 hover:bg-amber-600 hover:text-white",
                      else: "bg-amber-600 text-white hover:bg-amber-500"
                    )}
                  title="Generate Chef cues with AI"
                >
                  {if total_cues > 0, do: "REGEN", else: "GENERATE"}
                </button>
              <% end %>
            </div>
          </div>

          <%!-- Cue chips grid (paginated) --%>
          <%= if length(page_cues) > 0 do %>
            <div class="grid grid-cols-4 gap-1 mb-1">
              <%= for cue <- page_cues do %>
                <div class="relative group/chip">
                  <button
                    phx-click={
                      JS.dispatch("dj:seek",
                        to: "#dj-tab",
                        detail: %{deck: @deck_number, position: cue.position_ms / 1000.0}
                      )
                    }
                    class={"w-full px-1 py-1 text-[9px] font-mono rounded text-center transition-colors truncate leading-tight " <> auto_cue_chip_class(cue)}
                    title={"#{cue.label || "Cue"} · #{format_confidence(cue.confidence)} — click to seek"}
                  >
                    {format_ms(cue.position_ms)}
                  </button>
                  <button
                    phx-click="loop_from_cue"
                    phx-target={@myself}
                    phx-value-deck={@deck_number}
                    phx-value-cue_id={cue.id}
                    class="absolute top-0 right-0 opacity-0 group-hover/chip:opacity-100 w-3.5 h-3.5 flex items-center justify-center rounded-bl rounded-tr bg-purple-700 text-white text-[8px] transition-opacity"
                    title="Loop from this cue"
                  >⟲</button>
                </div>
              <% end %>
            </div>
            <%!-- Pagination --%>
            <div :if={total_pages > 1} class="flex items-center justify-between mt-1">
              <button
                phx-click="cue_page"
                phx-target={@myself}
                phx-value-deck={@deck_number}
                phx-value-page={@cue_page - 1}
                disabled={@cue_page <= 1}
                class={"px-1.5 py-0.5 text-[8px] font-bold rounded transition-colors " <>
                  if(@cue_page <= 1,
                    do: "bg-gray-800 text-gray-700 cursor-not-allowed",
                    else: "bg-gray-700 text-gray-400 hover:bg-gray-600"
                  )}
              >←</button>
              <span class="text-[8px] text-gray-600 font-mono">
                pg {@cue_page}/{total_pages} · {total_cues} cues
              </span>
              <button
                phx-click="cue_page"
                phx-target={@myself}
                phx-value-deck={@deck_number}
                phx-value-page={@cue_page + 1}
                disabled={@cue_page >= total_pages}
                class={"px-1.5 py-0.5 text-[8px] font-bold rounded transition-colors " <>
                  if(@cue_page >= total_pages,
                    do: "bg-gray-800 text-gray-700 cursor-not-allowed",
                    else: "bg-gray-700 text-gray-400 hover:bg-gray-600"
                  )}
              >→</button>
            </div>
          <% else %>
            <p :if={!@detecting_cues && @deck.track} class="text-[10px] text-gray-600 italic text-center py-0.5">
              No Chef cues · click GENERATE
            </p>
          <% end %>

          <%!-- Saved Chef Sets --%>
          <div :if={length(@chef_sets) > 0} class="mt-2 pt-1.5 border-t border-gray-700/20">
            <span class="text-[9px] text-gray-600 uppercase tracking-wider block mb-1">Saved Sets</span>
            <div class="space-y-0.5">
              <%= for cs <- @chef_sets do %>
                <div class="flex items-center gap-1 text-[9px]">
                  <button phx-click="load_chef_set" phx-target={@myself}
                    phx-value-deck={@deck_number} phx-value-set_id={cs.id}
                    class="flex-1 text-left px-1.5 py-0.5 rounded bg-gray-800 text-gray-300 hover:bg-amber-700/40 hover:text-amber-300 transition-colors truncate"
                    title={"Load: #{cs.name}"}>
                    {cs.name}
                  </button>
                  <button phx-click="delete_chef_set" phx-target={@myself}
                    phx-value-set_id={cs.id}
                    class="px-1 py-0.5 rounded bg-gray-800 text-gray-600 hover:bg-red-700/40 hover:text-red-400 transition-colors"
                    title="Delete set">×</button>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <%!-- Transport Controls --%>
      <div class="flex items-center gap-3 mb-4">
        <button
          phx-click={
            JS.dispatch("dj:play",
              to: "#dj-tab",
              detail: %{deck: @deck_number, playing: !@deck.playing}
            )
            |> JS.push("toggle_play",
              value: %{deck: to_string(@deck_number)},
              target: @myself
            )
          }
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

        <button
          phx-click="toggle_dj_midi_learn"
          phx-target={@myself}
          class={"px-2 py-1 text-xs font-bold rounded transition-colors ml-1 " <>
            if(@midi_learn_mode,
              do: "bg-yellow-500 text-black ring-1 ring-yellow-300/60 animate-pulse",
              else: "bg-gray-700 text-gray-400 hover:bg-gray-600 hover:text-gray-300"
            )}
          title="DJ MIDI Learn: click to enable, then click a control to assign MIDI"
        >
          LEARN
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
          <button
            id={"tap-tempo-btn-#{@deck_number}"}
            phx-click="tap_tempo"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            title="Tap tempo to sync BPM"
            class="px-2 py-1 text-[10px] font-bold rounded bg-gray-700 text-gray-400 hover:bg-amber-700 hover:text-white active:bg-amber-500 transition-colors select-none"
          >
            TAP
          </button>
          <span class="text-xs text-gray-500 uppercase">BPM</span>
          <span class={"text-lg font-bold font-mono " <>
            if(@deck.tempo_bpm > 0, do: "text-white", else: "text-gray-600")}>
            {format_bpm(@deck.tempo_bpm)}
          </span>
        </div>
      </div>

      <%!-- MIDI Learn Panel (shown when learn mode is active) --%>
      <%= if @midi_learn_mode do %>
        <div class="mb-3 border border-yellow-600/50 rounded-lg p-3 bg-yellow-950/20">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs text-yellow-400 font-bold uppercase tracking-wider flex items-center gap-1.5">
              <svg class="w-3 h-3 animate-pulse" fill="currentColor" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/></svg>
              MIDI Learn Active
            </span>
            <button
              phx-click="toggle_dj_midi_learn"
              phx-target={@myself}
              class="px-2 py-0.5 text-[9px] font-bold rounded bg-gray-700 text-gray-400 hover:bg-red-700 hover:text-white transition-colors"
            >
              DONE
            </button>
          </div>
          <p class="text-[9px] text-gray-500 mb-2">
            Click a control below to select it, then press/move a MIDI control. Stays active until DONE.
          </p>
          <%= if @midi_learn_target do %>
            <div class="text-[9px] text-yellow-300 bg-yellow-900/30 rounded px-2 py-1 mb-2 font-mono">
              Waiting for MIDI input → {@midi_learn_target["action"]}
              <%= if @midi_learn_target["deck"] do %>deck {@midi_learn_target["deck"]}<% end %>
              <%= if @midi_learn_target["slot"] do %>slot {@midi_learn_target["slot"]}<% end %>
            </div>
          <% end %>
          <%!-- Assignable controls grid --%>
          <div class="grid grid-cols-3 gap-1">
            <%= for {action, label, deck, slot} <- dj_learn_controls(@deck_number) do %>
              <% is_active = @midi_learn_target && @midi_learn_target["action"] == action && @midi_learn_target["deck"] == deck && @midi_learn_target["slot"] == slot %>
              <button
                phx-click="dj_learn_control"
                phx-target={@myself}
                phx-value-action={action}
                phx-value-deck={deck}
                phx-value-slot={slot}
                class={"px-1.5 py-1 text-[8px] font-bold rounded transition-all " <>
                  if(is_active,
                    do: "bg-yellow-500 text-black ring-1 ring-yellow-300 animate-pulse",
                    else: "bg-gray-700/80 text-gray-400 hover:bg-yellow-800/40 hover:text-yellow-300 border border-gray-600/30"
                  )}
              >
                {label}
              </button>
            <% end %>
          </div>
        </div>
      <% end %>

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

        <%!-- Loop size buttons + double/half time --%>
        <div class="space-y-1.5">
          <div class="flex items-center gap-1">
            <span class="text-[10px] text-gray-600 w-8">Size:</span>
            <%= for {label, beats} <- [{"⅛", "0.125"}, {"¼", "0.25"}, {"½", "0.5"}, {"1", "1"}, {"2", "2"}, {"4", "4"}, {"8", "8"}, {"16", "16"}, {"32", "32"}] do %>
              <button
                phx-click="loop_size"
                phx-target={@myself}
                phx-value-deck={@deck_number}
                phx-value-beats={beats}
                disabled={is_nil(@deck.track) || @deck.tempo_bpm <= 0}
                class={"flex-1 py-1 text-[10px] font-mono font-bold rounded text-center transition-colors " <>
                  cond do
                    is_nil(@deck.track) || @deck.tempo_bpm <= 0 -> "bg-gray-800 text-gray-700 cursor-not-allowed"
                    beats == @deck.loop_size_str -> "bg-purple-600 text-white ring-1 ring-purple-400/50"
                    true -> "bg-gray-700/80 text-gray-300 hover:bg-purple-700 hover:text-white active:bg-purple-500"
                  end}
              >
                {label}
              </button>
            <% end %>
          </div>
          <%!-- Double / Half time --%>
          <div class="flex items-center gap-1">
            <span class="text-[10px] text-gray-600 w-8">Time:</span>
            <button
              phx-click="set_time_factor"
              phx-target={@myself}
              phx-value-deck={@deck_number}
              phx-value-factor="0.5"
              disabled={is_nil(@deck.track)}
              class={"flex-1 py-1 text-[10px] font-mono font-bold rounded text-center transition-colors " <>
                if(is_nil(@deck.track),
                  do: "bg-gray-800 text-gray-700 cursor-not-allowed",
                  else: if(@deck.time_factor == 0.5,
                    do: "bg-violet-700 text-white ring-1 ring-violet-400/50",
                    else: "bg-gray-700/80 text-gray-300 hover:bg-violet-700 hover:text-white"
                  )
                )}
            >
              ½×
            </button>
            <button
              phx-click="set_time_factor"
              phx-target={@myself}
              phx-value-deck={@deck_number}
              phx-value-factor="1.0"
              disabled={is_nil(@deck.track)}
              class={"flex-1 py-1 text-[10px] font-mono font-bold rounded text-center transition-colors " <>
                if(is_nil(@deck.track),
                  do: "bg-gray-800 text-gray-700 cursor-not-allowed",
                  else: if(@deck.time_factor == 1.0,
                    do: "bg-gray-600 text-white ring-1 ring-gray-400/50",
                    else: "bg-gray-700/80 text-gray-300 hover:bg-gray-600 hover:text-white"
                  )
                )}
            >
              1×
            </button>
            <button
              phx-click="set_time_factor"
              phx-target={@myself}
              phx-value-deck={@deck_number}
              phx-value-factor="2.0"
              disabled={is_nil(@deck.track)}
              class={"flex-1 py-1 text-[10px] font-mono font-bold rounded text-center transition-colors " <>
                if(is_nil(@deck.track),
                  do: "bg-gray-800 text-gray-700 cursor-not-allowed",
                  else: if(@deck.time_factor == 2.0,
                    do: "bg-violet-700 text-white ring-1 ring-violet-400/50",
                    else: "bg-gray-700/80 text-gray-300 hover:bg-violet-700 hover:text-white"
                  )
                )}
            >
              2×
            </button>
          </div>
        </div>
      </div>

      <%!-- EQ Kill Switches + Filter --%>
      <div :if={@show_eq && @deck.track} class="mb-4 border border-gray-700/50 rounded-lg p-3">
        <div class="flex items-center gap-3 mb-2">
          <span class="text-xs text-gray-500 uppercase tracking-wider font-semibold w-8">EQ</span>
          <%= for band <- ["high", "mid", "low"] do %>
            <button
              phx-click="toggle_eq_kill"
              phx-target={@myself}
              phx-value-deck={@deck_number}
              phx-value-band={band}
              class={"flex-1 py-1.5 text-xs font-bold rounded uppercase transition-colors " <>
                if(Map.get(@deck.eq_kills, band),
                  do: "bg-red-700 text-white ring-1 ring-red-400/60",
                  else: "bg-gray-700 text-gray-400 hover:bg-gray-600"
                )}
            >
              {band}
            </button>
          <% end %>
        </div>
        <%!-- LP/HP Filter --%>
        <div class="flex items-center gap-2">
          <span class="text-[10px] text-gray-600 w-8">Filter:</span>
          <button
            phx-click="set_filter"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            phx-value-mode="hp"
            phx-value-cutoff={to_string(@deck.filter_cutoff)}
            class={"px-2 py-1 text-[10px] font-bold rounded transition-colors " <>
              if(@deck.filter_mode == "hp",
                do: "bg-sky-700 text-white",
                else: "bg-gray-700 text-gray-400 hover:bg-gray-600"
              )}
          >
            HP
          </button>
          <form phx-change="set_filter" phx-target={@myself} class="flex-1">
            <input type="hidden" name="deck" value={@deck_number} />
            <input type="hidden" name="mode" value={@deck.filter_mode} />
            <input
              type="range" name="cutoff" min="0" max="1" step="0.01"
              value={@deck.filter_cutoff}
              disabled={@deck.filter_mode == "none"}
              class={"w-full h-1.5 rounded appearance-none cursor-pointer " <>
                if(@deck_number == 1, do: "accent-cyan-500", else: "accent-orange-500")}
            />
          </form>
          <button
            phx-click="set_filter"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            phx-value-mode="lp"
            phx-value-cutoff={to_string(@deck.filter_cutoff)}
            class={"px-2 py-1 text-[10px] font-bold rounded transition-colors " <>
              if(@deck.filter_mode == "lp",
                do: "bg-amber-700 text-white",
                else: "bg-gray-700 text-gray-400 hover:bg-gray-600"
              )}
          >
            LP
          </button>
          <button
            phx-click="set_filter"
            phx-target={@myself}
            phx-value-deck={@deck_number}
            phx-value-mode="none"
            phx-value-cutoff="0.5"
            class={"px-2 py-1 text-[10px] font-bold rounded transition-colors " <>
              if(@deck.filter_mode == "none",
                do: "bg-gray-600 text-white",
                else: "bg-gray-800 text-gray-600 hover:bg-gray-700"
              )}
          >
            OFF
          </button>
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

  # -- Loop Track Deck Panel (Decks C/D) --

  attr :deck_number, :integer, required: true
  attr :deck, :map, required: true
  attr :tracks, :list, required: true
  attr :volume, :integer, required: true
  attr :cue_points, :list, required: true
  attr :deck_type, :string, default: "loop"
  attr :loop_pads, :list, default: []
  attr :pad_mode, :string, default: "loop"
  attr :poly_voices, :integer, default: 1
  attr :pad_fade, :string, default: "none"
  attr :active_pads, :list, default: []
  attr :alchemy_sets, :list, default: []
  attr :myself, :any, required: true

  defp loop_deck_panel(assigns) do
    label = if assigns.deck_number == 3, do: "C", else: "D"
    assigns = assign(assigns, :deck_label, label)

    ~H"""
    <div class={"bg-gray-900/80 rounded-xl p-3 border border-gray-700/40 " <>
      if(@deck.playing, do: "ring-1 ring-violet-500/30", else: "")}>
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-2">
          <span class="text-xs font-bold tracking-wider text-violet-400">DECK {@deck_label}</span>
          <form phx-change="set_deck_type" phx-target={@myself}>
            <input type="hidden" name="deck" value={to_string(@deck_number)} />
            <select name="deck_type"
              class="text-[9px] bg-gray-800 border border-gray-700/50 rounded px-1 py-0.5 text-gray-300 focus:outline-none focus:ring-1 focus:ring-violet-500/50 cursor-pointer">
              <option value="full" selected={@deck_type == "full"}>FULL</option>
              <option value="loop" selected={@deck_type == "loop"}>LOOP</option>
              <option value="soundboard" selected={@deck_type == "soundboard"}>SND</option>
            </select>
          </form>
        </div>
        <div class="flex items-center gap-2">
          <span :if={@deck.loop_active} class="text-[10px] px-1.5 py-0.5 rounded-full bg-violet-500/20 text-violet-400 font-bold animate-pulse">
            LOOP
          </span>
          <span class={"text-[10px] px-1.5 py-0.5 rounded-full " <>
            if(@deck.playing, do: "bg-green-500/20 text-green-400", else: "bg-gray-700 text-gray-600")}>
            {if @deck.playing, do: "PLAYING", else: "STOPPED"}
          </span>
        </div>
      </div>

      <p class="text-sm text-white font-medium truncate mb-2">
        {if @deck.track, do: @deck.track.title, else: if(@deck_type == "soundboard", do: "Empty — soundboard", else: "Empty — load a loop track")}
      </p>

      <%= if @deck_type == "soundboard" do %>
        <%!-- Soundboard header: Load Kit button (US-015) --%>
        <div class="flex items-center justify-between mb-2">
          <span class="text-[9px] text-gray-500 uppercase tracking-wider">Pads</span>
          <div class="flex items-center gap-1">
            <span class="text-[8px] text-gray-600">drag Splice samples onto pads</span>
            <button
              phx-click="open_kit_browser"
              phx-target={@myself}
              phx-value-deck={@deck_number}
              class="px-1.5 py-0.5 text-[8px] font-bold rounded bg-violet-900/50 text-violet-300 hover:bg-violet-800/60 border border-violet-700/40 transition-colors"
              title="Load a saved DrumKit onto these pads"
            >
              LOAD KIT
            </button>
          </div>
        </div>
        <%!-- Soundboard grid: 4×4 trigger pads with labels --%>
        <%
          snd_colors = ~w(#7c3aed #1d4ed8 #0e7490 #065f46 #92400e #b91c1c #be185d #6d28d9
                          #4f46e5 #0369a1 #0f766e #15803d #b45309 #c2410c #9f1239 #581c87)
        %>
        <div class="grid grid-cols-4 gap-1 mb-2">
          <%= for i <- 0..15 do %>
            <% pad = Enum.at(@loop_pads, rem(i, 8), %{assigned: false, position_ms: 0, label: nil, color: Enum.at(snd_colors, i, "#374151")}) %>
            <% is_active = rem(i, 8) in @active_pads %>
            <%!-- Pad: drag-and-drop Splice sample (US-015) --%>
            <div
              class="relative group/snd aspect-square"
              id={"pad-drop-#{@deck_number}-#{i}"}
              phx-hook="PadDropTarget"
              data-deck={@deck_number}
              data-pad={rem(i, 8)}
            >
              <button
                phx-click="trigger_loop_pad"
                phx-target={@myself}
                phx-value-deck={@deck_number}
                phx-value-pad={rem(i, 8)}
                disabled={!pad.assigned}
                class={"w-full h-full min-h-[36px] rounded text-[7px] font-bold transition-all active:scale-95 leading-tight " <>
                  if(!pad.assigned,
                    do: "border border-dashed border-gray-700/50 text-gray-700 cursor-not-allowed",
                    else: if(is_active, do: "ring-2 ring-white/60 scale-95", else: "hover:brightness-125 shadow")
                  )}
                style={"background-color: #{pad.color}; #{if pad.assigned, do: "color: white;", else: ""}"}
                title={if pad.assigned, do: pad.label || "Pad #{i + 1}", else: "Unassigned"}
              >
                {if pad.assigned, do: (pad.label || "#{i + 1}"), else: "#{i + 1}"}
              </button>
              <button
                :if={!pad.assigned && @deck.track}
                phx-click="assign_loop_pad"
                phx-target={@myself}
                phx-value-deck={@deck_number}
                phx-value-pad={rem(i, 8)}
                class="absolute inset-0 opacity-0 group-hover/snd:opacity-100 rounded flex items-center justify-center text-[7px] font-bold text-white transition-opacity"
                style={"background-color: #{Enum.at(snd_colors, i, "#374151")}cc;"}
              >
                SET
              </button>
            </div>
          <% end %>
        </div>

        <%!-- Soundboard playback mode strip --%>
        <div class="flex items-center gap-1 mb-2">
          <%= for {mode, lbl} <- [{"oneshot", "1-SHOT"}, {"loop", "LOOP"}, {"gate", "GATE"}] do %>
            <button
              phx-click="set_pad_mode" phx-target={@myself}
              phx-value-deck={@deck_number} phx-value-mode={mode}
              class={"flex-1 py-0.5 text-[8px] font-bold rounded transition-colors " <>
                if(@pad_mode == mode, do: "bg-violet-600 text-white", else: "bg-gray-800 text-gray-500 hover:bg-gray-700")}
            >
              {lbl}
            </button>
          <% end %>
          <div class="flex items-center gap-0.5 ml-auto">
            <span class="text-[7px] text-gray-600">V</span>
            <%= for v <- [1, 2, 4, 8] do %>
              <button phx-click="set_pad_poly" phx-target={@myself}
                phx-value-deck={@deck_number} phx-value-voices={v}
                class={"w-5 h-5 text-[7px] font-mono rounded " <>
                  if(@poly_voices == v, do: "bg-teal-700 text-white", else: "bg-gray-800 text-gray-500 hover:bg-gray-700")}>
                {v}
              </button>
            <% end %>
          </div>
        </div>
      <% else %>
      <%!-- Compact waveform --%>
      <div
        id={"waveform-deck-#{@deck_number}"}
        phx-update="ignore"
        class="rounded bg-gray-800 border border-gray-700/30 overflow-hidden mb-3"
        style="min-height: 60px;"
        data-deck={@deck_number}
      >
      </div>

      <%!-- Transport row --%>
      <div class="flex items-center gap-2 mb-2">
        <button
          phx-click={
            JS.dispatch("dj:play",
              to: "#dj-tab",
              detail: %{deck: @deck_number, playing: !@deck.playing}
            )
            |> JS.push("toggle_play",
              value: %{deck: to_string(@deck_number)},
              target: @myself
            )
          }
          disabled={is_nil(@deck.track)}
          class={"px-3 py-1.5 text-xs font-bold rounded transition-colors " <>
            cond do
              is_nil(@deck.track) -> "bg-gray-700 text-gray-600 cursor-not-allowed"
              @deck.playing -> "bg-green-600 text-white hover:bg-red-600"
              true -> "bg-violet-600 text-white hover:bg-violet-500"
            end}
        >
          {if @deck.playing, do: "■ STOP", else: "▶ PLAY"}
        </button>
        <span class="text-xs font-mono text-gray-400 flex-1 text-center">
          {Timecode.ms_to_smpte(trunc(@deck.position * 1000))}
        </span>
        <span :if={@deck.tempo_bpm > 0} class="text-[10px] text-violet-400 font-mono">
          {Float.round(@deck.tempo_bpm * (@deck.time_factor || 1.0), 1)} BPM
        </span>
      </div>

      <%!-- Loop controls (compact) --%>
      <div class="flex items-center gap-1 mb-2">
        <button phx-click="loop_in" phx-target={@myself} phx-value-deck={@deck_number}
          disabled={is_nil(@deck.track)}
          class={"px-2 py-1 text-[10px] font-bold rounded transition-colors " <>
            if(@deck.loop_start_ms != nil, do: "bg-violet-600 text-white", else: "bg-gray-700 text-gray-400 hover:bg-gray-600")}>
          IN
        </button>
        <button phx-click="loop_out" phx-target={@myself} phx-value-deck={@deck_number}
          disabled={is_nil(@deck.track) || is_nil(@deck.loop_start_ms)}
          class={"px-2 py-1 text-[10px] font-bold rounded transition-colors " <>
            if(@deck.loop_end_ms != nil, do: "bg-violet-600 text-white", else: "bg-gray-700 text-gray-400 hover:bg-gray-600")}>
          OUT
        </button>
        <button phx-click="loop_toggle" phx-target={@myself} phx-value-deck={@deck_number}
          disabled={is_nil(@deck.loop_start_ms) || is_nil(@deck.loop_end_ms)}
          class={"px-2 py-1 text-[10px] font-bold rounded transition-colors " <>
            if(@deck.loop_active, do: "bg-green-600 text-white ring-1 ring-green-400/50", else: "bg-gray-700 text-gray-400 hover:bg-gray-600")}>
          {if @deck.loop_active, do: "ON", else: "OFF"}
        </button>
        <%!-- Beat size quick-select --%>
        <%= for {label, beats} <- [{"1", "1"}, {"2", "2"}, {"4", "4"}, {"8", "8"}] do %>
          <button phx-click="loop_size" phx-target={@myself}
            phx-value-deck={@deck_number} phx-value-beats={beats}
            disabled={is_nil(@deck.track) || @deck.tempo_bpm <= 0}
            class={"flex-1 py-1 text-[10px] font-mono font-bold rounded text-center transition-colors " <>
              if(is_nil(@deck.track) || @deck.tempo_bpm <= 0,
                do: "bg-gray-800 text-gray-700 cursor-not-allowed",
                else: "bg-gray-700/80 text-gray-300 hover:bg-violet-700 hover:text-white"
              )}>
            {label}
          </button>
        <% end %>
        <%!-- Double/Half time --%>
        <button phx-click="set_time_factor" phx-target={@myself}
          phx-value-deck={@deck_number} phx-value-factor="0.5"
          disabled={is_nil(@deck.track)}
          class={"px-2 py-1 text-[10px] font-bold rounded transition-colors " <>
            if(@deck.time_factor == 0.5, do: "bg-violet-700 text-white", else: "bg-gray-700 text-gray-500 hover:bg-violet-700 hover:text-white")}>
          ½×
        </button>
        <button phx-click="set_time_factor" phx-target={@myself}
          phx-value-deck={@deck_number} phx-value-factor="2.0"
          disabled={is_nil(@deck.track)}
          class={"px-2 py-1 text-[10px] font-bold rounded transition-colors " <>
            if(@deck.time_factor == 2.0, do: "bg-violet-700 text-white", else: "bg-gray-700 text-gray-500 hover:bg-violet-700 hover:text-white")}>
          2×
        </button>
      </div>

      <%!-- Stem solo/mute strip --%>
      <% loop_stems = Enum.map(@deck.stems || [], &Atom.to_string(&1.stem_type)) %>
      <div :if={length(loop_stems) > 0} class="flex gap-1 mb-2">
        <%= for stem_type <- loop_stems do %>
          <% state = Map.get(@deck.stem_states, stem_type, "on") %>
          <div class="flex-1 flex flex-col items-center gap-0.5">
            <button phx-click="toggle_stem_state" phx-target={@myself}
              phx-value-deck={@deck_number} phx-value-stem={stem_type} phx-value-mode="solo"
              class={"w-full py-0.5 text-[8px] font-bold rounded " <>
                if(state == "solo", do: "bg-yellow-500 text-black", else: "bg-gray-800 text-gray-600 hover:bg-gray-700")}>
              S
            </button>
            <div class={"w-full text-[8px] font-bold text-center py-0.5 rounded " <>
              if(state == "mute", do: "bg-gray-800 text-gray-700", else: "bg-violet-900/40 text-violet-400")}>
              {String.slice(stem_type, 0, 3)}
            </div>
            <button phx-click="toggle_stem_state" phx-target={@myself}
              phx-value-deck={@deck_number} phx-value-stem={stem_type} phx-value-mode="mute"
              class={"w-full py-0.5 text-[8px] font-bold rounded " <>
                if(state == "mute", do: "bg-red-700 text-white", else: "bg-gray-800 text-gray-600 hover:bg-gray-700")}>
              M
            </button>
          </div>
        <% end %>
      </div>
      <% end %>

      <%!-- Loop Pad Grid (MPC-style 4×2) — shown for loop deck type --%>
      <%= if @deck_type != "soundboard" do %>
      <div class="mb-2">
        <%!-- Pad mode + poly + fade controls --%>
        <div class="flex items-center gap-1 mb-1.5">
          <%!-- Mode: one-shot / loop / gate --%>
          <%= for {mode, lbl} <- [{"oneshot", "1-SHOT"}, {"loop", "LOOP"}, {"gate", "GATE"}] do %>
            <button
              phx-click="set_pad_mode"
              phx-target={@myself}
              phx-value-deck={@deck_number}
              phx-value-mode={mode}
              class={"flex-1 py-0.5 text-[8px] font-bold rounded transition-colors " <>
                if(@pad_mode == mode,
                  do: "bg-violet-600 text-white",
                  else: "bg-gray-800 text-gray-500 hover:bg-gray-700"
                )}
            >
              {lbl}
            </button>
          <% end %>
          <%!-- Poly voices --%>
          <div class="flex items-center gap-0.5 ml-1">
            <span class="text-[8px] text-gray-600 font-mono">V</span>
            <%= for v <- [1, 2, 4] do %>
              <button
                phx-click="set_pad_poly"
                phx-target={@myself}
                phx-value-deck={@deck_number}
                phx-value-voices={v}
                class={"w-5 h-5 text-[8px] font-mono rounded transition-colors " <>
                  if(@poly_voices == v,
                    do: "bg-teal-700 text-white",
                    else: "bg-gray-800 text-gray-500 hover:bg-gray-700"
                  )}
              >
                {v}
              </button>
            <% end %>
          </div>
          <%!-- Fade --%>
          <div class="flex items-center gap-0.5 ml-1">
            <%= for {fade, lbl} <- [{"none", "—"}, {"in", "FI"}, {"out", "FO"}, {"cross", "FX"}] do %>
              <button
                phx-click="set_pad_fade"
                phx-target={@myself}
                phx-value-deck={@deck_number}
                phx-value-fade={fade}
                class={"w-5 h-5 text-[7px] font-bold rounded transition-colors " <>
                  if(@pad_fade == fade,
                    do: "bg-amber-700 text-white",
                    else: "bg-gray-800 text-gray-600 hover:bg-gray-700"
                  )}
                title={case fade do
                  "none" -> "No fade"
                  "in" -> "Fade in"
                  "out" -> "Fade out"
                  "cross" -> "Crossfade"
                  _ -> fade
                end}
              >
                {lbl}
              </button>
            <% end %>
          </div>
        </div>

        <%!-- 4×2 Pad Grid --%>
        <div class="grid grid-cols-4 gap-1">
          <%= for {pad, idx} <- Enum.with_index(@loop_pads) do %>
            <% is_active = idx in @active_pads %>
            <div class="relative group/pad aspect-square">
              <%!-- Main pad button --%>
              <button
                phx-click="trigger_loop_pad"
                phx-target={@myself}
                phx-value-deck={@deck_number}
                phx-value-pad={idx}
                disabled={is_nil(@deck.track)}
                class={"w-full h-full min-h-[40px] rounded text-[8px] font-bold transition-all active:scale-95 " <>
                  cond do
                    is_nil(@deck.track) -> "bg-gray-900 border border-gray-800 text-gray-700 cursor-not-allowed"
                    !pad.assigned -> "bg-gray-800/60 border border-gray-700/50 text-gray-600 hover:bg-gray-700 hover:border-gray-600"
                    is_active -> "ring-2 ring-white/40 shadow-lg scale-95"
                    true -> "hover:brightness-125 active:scale-95 shadow-sm"
                  end}
                style={if pad.assigned, do: "background-color: #{pad.color}; color: white;", else: ""}
                title={if pad.assigned, do: "#{pad.label} — click to trigger#{if @pad_mode == "loop", do: " (loop)", else: ""}", else: "No assignment — click to assign current position"}
              >
                <%= if pad.assigned do %>
                  <div class="flex flex-col items-center gap-0 leading-none">
                    <span class="text-[9px] font-mono">{pad.label}</span>
                    <span :if={@pad_mode == "loop"} class="text-[7px] opacity-70">↻</span>
                    <span :if={@pad_mode == "oneshot"} class="text-[7px] opacity-70">▶</span>
                    <span :if={@pad_mode == "gate"} class="text-[7px] opacity-70">▤</span>
                  </div>
                <% else %>
                  <span class="text-gray-600">{idx + 1}</span>
                <% end %>
              </button>
              <%!-- Assign overlay on hover (empty pad) --%>
              <button
                :if={!pad.assigned && @deck.track}
                phx-click="assign_loop_pad"
                phx-target={@myself}
                phx-value-deck={@deck_number}
                phx-value-pad={idx}
                class="absolute inset-0 opacity-0 group-hover/pad:opacity-100 rounded bg-violet-600/80 text-white text-[8px] font-bold transition-opacity flex items-center justify-center"
                title="Assign current position to pad #{idx + 1}"
              >
                SET
              </button>
              <%!-- Clear overlay on hover (assigned pad) --%>
              <button
                :if={pad.assigned}
                phx-click="clear_loop_pad"
                phx-target={@myself}
                phx-value-deck={@deck_number}
                phx-value-pad={idx}
                class="absolute -top-1 -right-1 opacity-0 group-hover/pad:opacity-100 w-3.5 h-3.5 flex items-center justify-center rounded-full bg-red-600 text-white text-[8px] font-bold transition-opacity shadow"
                title="Clear pad #{idx + 1}"
              >
                ×
              </button>
            </div>
          <% end %>
        </div>
        <div class="flex justify-between mt-0.5 px-0.5">
          <span class="text-[7px] text-gray-700 font-mono">1–4</span>
          <span class="text-[7px] text-gray-700 font-mono">5–8</span>
        </div>
      </div>
      <% end %>

      <%!-- Load from Alchemy --%>
      <div :if={@alchemy_sets != []} class="mt-2">
        <form phx-change="load_alchemy_set" phx-target={@myself} phx-value-deck={@deck_number}>
          <select name="alchemy_set_id"
            class="w-full px-2 py-1 bg-gray-900 border border-violet-700/50 rounded text-[10px] text-violet-300 focus:outline-none focus:ring-1 focus:ring-violet-500">
            <option value="">✦ Load from Alchemy...</option>
            <%= for set <- @alchemy_sets, set.status == "complete" do %>
              <option value={set.id}>{set.name} (#{length(set.source_track_ids)} tracks)</option>
            <% end %>
          </select>
        </form>
      </div>

      <%!-- Track Loader --%>
      <form phx-change="load_track" phx-target={@myself} phx-value-deck={@deck_number}>
        <select name="track_id"
          class="w-full px-2 py-1 bg-gray-800 border border-gray-700 rounded text-xs text-gray-300 focus:outline-none focus:ring-1 focus:ring-violet-500">
          <option value="">Load loop track...</option>
          <%= for track <- @tracks do %>
            <option value={track.id} selected={@deck.track && @deck.track.id == track.id}>
              {track.title}{if track.artist, do: " — #{track.artist}", else: ""}
            </option>
          <% end %>
        </select>
      </form>
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
                <div :for={loop <- stem_loops_for_stem(@stem_loops, stem.id)} class="flex flex-col gap-1">
                  <div class="flex items-center gap-0.5">
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
                  <%!-- 8-step gate pattern for this stem loop --%>
                  <div class="flex items-center gap-0.5" title="Step gate: click steps to enable/disable this loop on each beat">
                    <%= for {active, step_idx} <- Enum.with_index(loop.steps || List.duplicate(true, 8)) do %>
                      <button
                        phx-click="toggle_stem_loop_step"
                        phx-target={@myself}
                        phx-value-deck={@deck_number}
                        phx-value-loop_id={loop.id}
                        phx-value-step={step_idx}
                        class={"w-4 h-3 rounded-sm transition-colors " <>
                          if(active,
                            do: "opacity-90",
                            else: "bg-gray-800 opacity-40"
                          )}
                        style={if active, do: "background-color: #{loop.color || stem_type_color(stem_type)};", else: ""}
                        title={"Step #{step_idx + 1}: #{if active, do: "ON", else: "OFF"}"}
                      />
                    <% end %>
                  </div>
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

  # Restores deck state from a persisted DeckSession on mount/reconnect.
  # When the LiveView crashes and reconnects, this re-hydrates the deck UI
  # without requiring the user to re-select the track.
  defp restore_deck_from_db(socket, user_id, deck_number) when is_integer(user_id) do
    case DJ.get_deck_state(user_id, deck_number) do
      %{session: session} when not is_nil(session.track_id) ->
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

        # Merge with empty_deck_state so new fields always have defaults
        deck_state =
          Map.merge(empty_deck_state(), %{
            track: track,
            playing: false,
            tempo_bpm: session.tempo_bpm || tempo || 0.0,
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
          })

        deck_key = deck_assign_key(deck_number)
        cue_points_key = cue_points_assign_key(deck_number)
        cue_points = DJ.list_cue_points(track.id, user_id)

        if track, do: SoundForgeWeb.Endpoint.subscribe("tracks:#{track.id}")

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

      _ ->
        socket
    end
  end

  defp restore_deck_from_db(socket, _user_id, _deck_number), do: socket

  defp empty_pad do
    %{assigned: false, position_ms: 0, end_ms: nil, label: nil, color: "#374151"}
  end

  defp default_loop_pads do
    Enum.map(0..7, fn _ -> empty_pad() end)
  end

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
      current_section: nil,
      # DJ best-practices fields
      time_factor: 1.0,
      eq_kills: %{"low" => false, "mid" => false, "high" => false},
      filter_mode: "none",
      filter_cutoff: 0.5,
      slip_mode: false,
      stem_states: %{},
      loop_size_beats: 4.0,
      loop_size_str: "4"
    }
  end

  defp deck_assign_key(1), do: :deck_1
  defp deck_assign_key(2), do: :deck_2
  defp deck_assign_key(3), do: :deck_3
  defp deck_assign_key(4), do: :deck_4

  defp cue_points_assign_key(1), do: :deck_1_cue_points
  defp cue_points_assign_key(2), do: :deck_2_cue_points
  defp cue_points_assign_key(3), do: :deck_3_cue_points
  defp cue_points_assign_key(4), do: :deck_4_cue_points

  defp stem_loops_assign_key(1), do: :deck_1_stem_loops
  defp stem_loops_assign_key(2), do: :deck_2_stem_loops
  defp stem_loops_assign_key(3), do: :deck_3_stem_loops
  defp stem_loops_assign_key(4), do: :deck_4_stem_loops

  defp stem_loops_open_key(1), do: :deck_1_stem_loops_open
  defp stem_loops_open_key(2), do: :deck_2_stem_loops_open
  defp stem_loops_open_key(3), do: :deck_3_stem_loops_open
  defp stem_loops_open_key(4), do: :deck_4_stem_loops_open

  defp detecting_cues_key(1), do: :detecting_cues_deck_1
  defp detecting_cues_key(2), do: :detecting_cues_deck_2
  defp detecting_cues_key(3), do: :detecting_cues_deck_3
  defp detecting_cues_key(4), do: :detecting_cues_deck_4

  defp cue_point_colors do
    ["#ef4444", "#f97316", "#eab308", "#22c55e", "#06b6d4", "#3b82f6", "#8b5cf6", "#ec4899"]
  end

  # Hot Cue A-H default colors (Traktor-inspired)
  @hot_cue_colors %{
    "A" => "#ef4444",  # red
    "B" => "#3b82f6",  # blue
    "C" => "#22c55e",  # green
    "D" => "#eab308",  # yellow
    "E" => "#8b5cf6",  # purple
    "F" => "#06b6d4",  # cyan
    "G" => "#f97316",  # orange
    "H" => "#e5e7eb"   # light gray / white
  }

  defp hot_cue_color(letter), do: Map.get(@hot_cue_colors, letter, "#6b7280")

  # Stem type → Tailwind color name (used in dynamic class strings)
  defp stem_color("vocals"), do: "purple"
  defp stem_color("drums"), do: "orange"
  defp stem_color("bass"), do: "green"
  defp stem_color("guitar"), do: "yellow"
  defp stem_color("piano"), do: "blue"
  defp stem_color(_), do: "cyan"

  # Stem type → hex color for inline styles (where dynamic Tailwind classes won't purge)
  defp stem_color_hex("vocals"), do: "#8b5cf6"
  defp stem_color_hex("drums"), do: "#f97316"
  defp stem_color_hex("bass"), do: "#22c55e"
  defp stem_color_hex("guitar"), do: "#eab308"
  defp stem_color_hex("piano"), do: "#3b82f6"
  defp stem_color_hex(_), do: "#06b6d4"

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

  defp build_stem_urls(stems, track) when is_list(stems) and stems != [] do
    available =
      Enum.filter(stems, fn stem ->
        stem.file_path && File.exists?(Path.expand(stem.file_path))
      end)

    if available != [] do
      Enum.map(available, fn stem ->
        relative = make_relative_path(stem.file_path)
        %{type: to_string(stem.stem_type), url: "/files/#{relative}"}
      end)
    else
      # All stem files are missing from disk (e.g. /tmp wiped) — fall back to full download
      build_stem_urls([], track)
    end
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

      # Handle _build symlink paths: _build/dev/lib/app/priv/uploads/...
      # These are the same physical directory as priv/uploads/ (hardlinked by Mix).
      true ->
        case Regex.run(~r{/_build/[^/]+/lib/[^/]+/priv/uploads/(.+)$}, expanded) do
          [_, rest] -> rest
          nil -> path
        end
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

  # Color-code auto-cue chips by label type.
  defp auto_cue_chip_class(cue) do
    label = cue.label || ""

    cond do
      String.contains?(label, "increase") ->
        "bg-cyan-900/40 text-cyan-300 hover:bg-cyan-800/60 border border-cyan-700/30"

      String.contains?(label, "decrease") ->
        "bg-orange-900/40 text-orange-300 hover:bg-orange-800/60 border border-orange-700/30"

      String.contains?(label, "Build") ->
        "bg-purple-900/40 text-purple-300 hover:bg-purple-800/60 border border-purple-700/30"

      true ->
        "bg-amber-900/30 text-amber-400/80 hover:bg-amber-800/40 border border-amber-700/20"
    end
  end

  # Convert position (seconds) + BPM to BAR.BEAT.TK string (4/4, 24 MIDI ticks/beat).
  defp position_to_bar_beat(position_secs, bpm) when is_number(bpm) and bpm > 0 and is_number(position_secs) and position_secs >= 0 do
    beat_length = 60.0 / bpm
    total_beat_float = position_secs / beat_length
    total_beats_int = trunc(total_beat_float)
    bar = div(total_beats_int, 4) + 1
    beat = rem(total_beats_int, 4) + 1
    tick = trunc((total_beat_float - total_beats_int) * 24) + 1
    "#{bar}.#{beat}.#{String.pad_leading(to_string(tick), 2, "0")}"
  end

  defp position_to_bar_beat(_, _), do: "1.1.01"

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

  # Returns a list of {action, label, deck, slot} tuples for the MIDI learn panel.
  # deck and slot are string values (passed as phx-value params) or nil.
  defp dj_learn_controls(deck_number) do
    d = to_string(deck_number)

    [
      {"dj_play", "Play/Pause", d, nil},
      {"dj_pitch", "Pitch", d, nil},
      {"dj_volume", "Volume", d, nil},
      {"dj_sync", "Sync", d, nil},
      {"dj_loop_toggle", "Loop", d, nil},
      {"dj_loop_size", "Loop Size", d, nil},
      {"dj_filter", "Filter", d, nil},
      {"dj_eq_high", "EQ Hi", d, nil},
      {"dj_eq_mid", "EQ Mid", d, nil},
      {"dj_eq_low", "EQ Lo", d, nil},
      {"dj_crossfader", "Crossfader", nil, nil},
      {"dj_cue", "Cue 1", d, "1"},
      {"dj_cue", "Cue 2", d, "2"},
      {"dj_cue", "Cue 3", d, "3"},
      {"dj_cue", "Cue 4", d, "4"}
    ]
  end
  # Convert deck number (1-4) to letter (A-D) for display.
  defp deck_letter(1), do: "A"
  defp deck_letter(2), do: "B"
  defp deck_letter(3), do: "C"
  defp deck_letter(4), do: "D"
  defp deck_letter(n), do: to_string(n)
end
