defmodule SoundForgeWeb.DjLive do
  @moduledoc """
  DJ LiveView with dual-deck layout.

  Provides two independent audio decks with WaveSurfer waveform displays,
  transport controls, BPM display, and a central crossfader. Tracks can
  be loaded from the user's library into either deck.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Music
  alias SoundForge.DJ
  alias SoundForge.DJ.Timecode

  @impl true
  def mount(_params, session, socket) do
    scope = socket.assigns[:current_scope] || load_scope_from_session(session)
    current_user_id = resolve_user_id(scope, session)

    tracks = list_user_tracks(scope)

    if connected?(socket), do: SoundForge.MIDI.Clock.subscribe()

    socket =
      socket
      |> assign(:current_scope, scope)
      |> assign(:current_user_id, current_user_id)
      |> assign(:page_title, "DJ - Sound Forge Alchemy")
      |> assign(:tracks, tracks)
      |> assign(:crossfader, 0)
      |> assign(:crossfader_curve, "linear")
      |> assign(:deck_1_volume, 100)
      |> assign(:deck_2_volume, 100)
      |> assign(:deck_1, empty_deck_state())
      |> assign(:deck_2, empty_deck_state())
      |> assign(:deck_1_cue_points, [])
      |> assign(:deck_2_cue_points, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"load_track" => track_id}, _uri, socket) when track_id != "" do
    user_id = socket.assigns[:current_user_id]

    if user_id do
      case DJ.load_track_to_deck(user_id, 1, track_id) do
        {:ok, session} ->
          track = session.track
          stems = if track, do: track.stems || [], else: []
          audio_urls = build_stem_urls(stems, track)

          pitch = session.pitch_adjust || 0.0
          {tempo, beat_times} = extract_analysis_data(track)

          cue_points =
            if track do
              DJ.list_cue_points(track.id, user_id)
            else
              []
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
            midi_sync: false
          }

          socket =
            socket
            |> assign(:deck_1, deck_state)
            |> assign(:deck_1_cue_points, cue_points)
            |> push_event("load_deck_audio", %{
              deck: 1,
              urls: audio_urls,
              track_title: track && track.title,
              tempo: tempo,
              beat_times: beat_times
            })
            |> push_event("set_cue_points", %{
              deck: 1,
              cue_points: encode_cue_points(cue_points)
            })
            |> push_event("set_pitch", %{deck: 1, value: pitch})

          {:noreply, socket}

        _ ->
          {:noreply, put_flash(socket, :error, "Failed to load track to deck 1")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

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

          # Extract analysis data for beat grid
          {tempo, beat_times} = extract_analysis_data(track)

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
            loop_end_ms: nil
          }

          deck_key = deck_assign_key(deck_number)
          cue_points_key = cue_points_assign_key(deck_number)

          # Load cue points for this track
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
              beat_times: beat_times
            })
            |> push_event("set_cue_points", %{
              deck: deck_number,
              cue_points: encode_cue_points(cue_points)
            })
            |> push_event("set_pitch", %{
              deck: deck_number,
              value: pitch
            })

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
      Phoenix.PubSub.broadcast(SoundForge.PubSub, "dj:transport", {:dj_transport, deck_number, transport_event})

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
  def handle_event("keydown", %{"key" => "z"}, socket) do
    new_value = max(socket.assigns.crossfader - 5, -100)

    socket =
      socket
      |> assign(:crossfader, new_value)
      |> push_event("set_crossfader", %{value: new_value})

    {:noreply, socket}
  end

  @impl true
  def handle_event("keydown", %{"key" => "x"}, socket) do
    new_value = min(socket.assigns.crossfader + 5, 100)

    socket =
      socket
      |> assign(:crossfader, new_value)
      |> push_event("set_crossfader", %{value: new_value})

    {:noreply, socket}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  # -- Virtual Controller Jog Events --

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
  def handle_event("jog_cue_press", %{"deck" => _deck_str}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("jog_cue_release", %{"deck" => _deck_str}, socket) do
    {:noreply, socket}
  end

  # -- MIDI Sync Controls --

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

      # Ensure loop_end is after loop_start
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
      # If no loop_start_ms set, use current position quantized to nearest beat
      loop_start =
        deck.loop_start_ms || quantize_to_beat(trunc(deck.position * 1000), deck.tempo_bpm)

      # Calculate loop length in ms: beats * (60000 / bpm)
      loop_length_ms = trunc(beats * (60_000 / deck.tempo_bpm))
      loop_end = loop_start + loop_length_ms

      updated_deck = %{
        deck
        | loop_start_ms: loop_start,
          loop_end_ms: loop_end,
          loop_active: true
      }

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

  # -- Pitch / Tempo Controls --

  @impl true
  def handle_event("set_pitch", %{"deck" => deck_str, "value" => value_str}, socket) do
    deck_number = String.to_integer(deck_str)
    deck_key = deck_assign_key(deck_number)
    deck = Map.get(socket.assigns, deck_key)

    # HTML range sends -80..80 (tenths); divide by 10 to get -8.0..8.0
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
      # The other deck's adjusted BPM
      other_adjusted_bpm = other.tempo_bpm * (1.0 + other.pitch_adjust / 100.0)
      # Calculate pitch this deck needs to match that BPM
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

      pitch_1 = ((avg_bpm / deck_1.tempo_bpm - 1.0) * 100.0) |> max(-8.0) |> min(8.0) |> Float.round(1)
      pitch_2 = ((avg_bpm / deck_2.tempo_bpm - 1.0) * 100.0) |> max(-8.0) |> min(8.0) |> Float.round(1)

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
            |> push_event("seek_and_play", %{
              deck: deck_number,
              position: position_sec
            })

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

  # -- MIDI Clock handle_info --

  @impl true
  def handle_info({:bpm_update, external_bpm}, socket) do
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

    {:noreply, socket}
  end

  @impl true
  def handle_info({:transport, transport_event}, socket) do
    socket =
      Enum.reduce([{:deck_1, 1}, {:deck_2, 2}], socket, fn {deck_key, deck_number}, acc ->
        deck = Map.get(acc.assigns, deck_key)

        if deck.midi_sync && deck.track do
          case transport_event do
            :start ->
              updated_deck = %{deck | playing: true}

              Phoenix.PubSub.broadcast(
                SoundForge.PubSub,
                "dj:transport",
                {:dj_transport, deck_number, :play}
              )

              acc
              |> assign(deck_key, updated_deck)
              |> push_event("play_deck", %{deck: deck_number, playing: true})

            :stop ->
              updated_deck = %{deck | playing: false}

              Phoenix.PubSub.broadcast(
                SoundForge.PubSub,
                "dj:transport",
                {:dj_transport, deck_number, :pause}
              )

              acc
              |> assign(deck_key, updated_deck)
              |> push_event("play_deck", %{deck: deck_number, playing: false})

            :continue ->
              updated_deck = %{deck | playing: true}

              Phoenix.PubSub.broadcast(
                SoundForge.PubSub,
                "dj:transport",
                {:dj_transport, deck_number, :play}
              )

              acc
              |> assign(deck_key, updated_deck)
              |> push_event("play_deck", %{deck: deck_number, playing: true})

            _ ->
              acc
          end
        else
          acc
        end
      end)

    {:noreply, socket}
  end

  # -- Virtual Controller handle_info --

  @impl true
  def handle_info({:virtual_controller, :trigger_cue, %{deck: deck_number, slot: slot}}, socket) do
    cue_points_key = if deck_number == 1, do: :deck_1_cue_points, else: :deck_2_cue_points
    cue_points = Map.get(socket.assigns, cue_points_key, [])
    cue = Enum.at(cue_points, slot - 1)

    if cue do
      deck_key = if deck_number == 1, do: :deck_1, else: :deck_2
      deck = Map.get(socket.assigns, deck_key)
      position = cue.position_ms / 1000

      updated_deck = %{deck | playing: true, position: position}

      socket =
        socket
        |> assign(deck_key, updated_deck)
        |> push_event("seek_and_play", %{deck: deck_number, position: position})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # -- Template --

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="dj-view"
      phx-hook="DjDeck"
      phx-window-keydown="keydown"
      class="min-h-screen bg-gray-800 p-4 md:p-6"
    >
      <div class="max-w-7xl mx-auto">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold text-white tracking-wide">DJ MODE</h1>
          <.link navigate={~p"/"} class="text-gray-400 hover:text-white text-sm transition-colors">
            Back to Library
          </.link>
        </div>

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
          />

          <%!-- DECK 2 --%>
          <.deck_panel
            deck_number={2}
            deck={@deck_2}
            tracks={@tracks}
            volume={@deck_2_volume}
            cue_points={@deck_2_cue_points}
            midi_sync={@deck_2.midi_sync}
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
                name="value"
                aria-label="Crossfader"
                class="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-purple-500"
              />
              <div class="flex justify-between w-full mt-1">
                <span class="text-xs text-gray-600">A</span>
                <span class="text-xs text-gray-600">|</span>
                <span class="text-xs text-gray-600">B</span>
              </div>
              <%!-- Keyboard hint --%>
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

  # -- Components --

  attr :deck_number, :integer, required: true
  attr :deck, :map, required: true
  attr :tracks, :list, required: true
  attr :volume, :integer, required: true
  attr :cue_points, :list, required: true
  attr :midi_sync, :boolean, default: false

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

      <%!-- WaveSurfer Waveform with Minimap --%>
      <div class="relative mb-4">
        <div
          id={"waveform-deck-#{@deck_number}"}
          class="rounded bg-gray-800 border border-gray-700/30 overflow-hidden"
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

      <%!-- Cue Point Pads --%>
      <div class="mb-4 border border-gray-700/50 rounded-lg p-3">
        <div class="flex items-center justify-between mb-2">
          <span class="text-xs text-gray-500 uppercase tracking-wider font-semibold">Hot Cues</span>
          <button
            phx-click="set_cue"
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
                phx-value-deck={@deck_number}
                phx-value-cue_id={cue.id}
                data-long-press-event="delete_cue"
                data-long-press-deck={@deck_number}
                data-long-press-cue-id={cue.id}
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
        <%!-- Play/Pause --%>
        <button
          phx-click="toggle_play"
          phx-value-deck={@deck_number}
          disabled={is_nil(@deck.track)}
          aria-label={if @deck.playing, do: "Pause deck #{@deck_number}", else: "Play deck #{@deck_number}"}
          class={"w-12 h-12 rounded-full flex items-center justify-center transition-colors " <>
            if(is_nil(@deck.track),
              do: "bg-gray-700 text-gray-600 cursor-not-allowed",
              else: if(@deck.playing,
                do: "bg-purple-600 hover:bg-purple-500 text-white",
                else: "bg-purple-600 hover:bg-purple-500 text-white"
              )
            )}
        >
          <svg
            :if={!@deck.playing}
            class="w-5 h-5 ml-0.5"
            fill="currentColor"
            viewBox="0 0 24 24"
          >
            <path d="M8 5v14l11-7z" />
          </svg>
          <svg :if={@deck.playing} class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
            <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
          </svg>
        </button>

        <%!-- Position / Time --%>
        <span class="text-sm text-gray-400 font-mono">
          {format_position(@deck.position)}
        </span>
        <%!-- SMPTE Timecode --%>
        <span class="text-xs text-gray-500 font-mono ml-1" title="SMPTE timecode (30fps)">
          {Timecode.ms_to_smpte(@deck.position * 1000)}
        </span>

        <%!-- MIDI Sync Toggle --%>
        <button
          phx-click="toggle_midi_sync"
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

        <%!-- BPM Display --%>
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

        <%!-- Horizontal Pitch Slider --%>
        <form phx-change="set_pitch" phx-value-deck={@deck_number} class="mb-2">
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

        <%!-- Adjusted BPM + Sync --%>
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
          <%!-- Loop Active Indicator --%>
          <span
            :if={@deck.loop_active}
            class={"text-xs px-2 py-0.5 rounded-full font-bold animate-pulse " <>
              if(@deck_number == 1, do: "bg-cyan-500/20 text-cyan-400", else: "bg-orange-500/20 text-orange-400")}
          >
            LOOP
          </span>
        </div>

        <%!-- Loop In / Out Buttons --%>
        <div class="flex items-center gap-2 mb-2">
          <button
            phx-click="loop_in"
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

          <%!-- Loop Toggle --%>
          <button
            phx-click="loop_toggle"
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

        <%!-- Beat Size Preset Buttons --%>
        <div class="flex items-center gap-1">
          <span class="text-xs text-gray-600 mr-1">Beats:</span>
          <button
            :for={{label, beats} <- [{"1/4", "0.25"}, {"1/2", "0.5"}, {"1", "1"}, {"2", "2"}, {"4", "4"}, {"8", "8"}]}
            phx-click="loop_size"
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
          <form phx-change="set_deck_volume" phx-value-deck={@deck_number} class="flex-1 flex items-center gap-2">
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
        <form phx-change="load_track" phx-value-deck={@deck_number}>
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
      midi_sync: false
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

  defp extract_analysis_data(nil), do: {nil, []}

  defp extract_analysis_data(track) do
    track = SoundForge.Repo.preload(track, :analysis_results)

    case track.analysis_results do
      [result | _] when not is_nil(result) ->
        beat_times = (result.features || %{}) |> Map.get("beat_times", [])
        {result.tempo, beat_times}

      _ ->
        {nil, []}
    end
  end

  @doc false
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
      {:ok, session} ->
        DJ.update_deck_session(session, %{pitch_adjust: pitch})

      _ ->
        :ok
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

      %{
        type: to_string(stem.stem_type),
        url: "/files/#{relative}"
      }
    end)
  end

  defp build_stem_urls([], track) when not is_nil(track) do
    # No stems, try the downloaded file
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

  defp format_bpm(bpm) when is_float(bpm) and bpm > 0, do: :erlang.float_to_binary(bpm, decimals: 1)
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

  defp load_scope_from_session(session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _inserted_at} <- SoundForge.Accounts.get_user_by_session_token(token) do
      SoundForge.Accounts.Scope.for_user(user)
    else
      _ -> nil
    end
  end

  defp resolve_user_id(%{user: %{id: id}}, _session), do: id

  defp resolve_user_id(_, session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _inserted_at} <- SoundForge.Accounts.get_user_by_session_token(token) do
      user.id
    else
      _ -> nil
    end
  end
end
