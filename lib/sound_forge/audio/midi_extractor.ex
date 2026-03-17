defmodule SoundForge.Audio.MidiExtractor do
  @moduledoc """
  Extracts a quantized MIDI drum pattern from detected drum events.

  Takes a track's drum_events (from transient detection) and BPM,
  snaps each event to the nearest 16th-note grid position, and
  writes a Type 0 MIDI file with one channel per drum category.

  ## GM Drum Map (Channel 10, 0-indexed: channel 9)
  - Kick       → note 36 (C2)
  - Snare      → note 38 (D2)
  - Hi-Hat     → note 42 (F#2 closed) / 46 (open)
  - Clap       → note 39 (D#2)
  - Perc/Other → note 37 (C#2)
  """

  import Bitwise

  @ticks_per_quarter 480
  # 16th note = quarter / 4
  @ticks_per_16th div(@ticks_per_quarter, 4)

  @drum_notes %{
    "kick" => 36,
    "snare" => 38,
    "hihat" => 42,
    "clap" => 39,
    "perc" => 37
  }

  @doc """
  Extract a MIDI file from drum events + BPM and write to the given output path.

  ## Parameters
  - drum_events: list of %{time_s: float, category: string, confidence: float}
  - bpm: float or integer (beats per minute)
  - output_path: absolute file path where .mid will be written

  Returns {:ok, output_path} or {:error, reason}.
  """
  @spec extract(list(map()), float(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def extract(drum_events, bpm, output_path) when is_list(drum_events) and bpm > 0 do
    tempo_us = round(60_000_000 / bpm)
    sixteenth_s = 60.0 / bpm / 4.0

    # Quantize each event to nearest 16th note tick
    events =
      drum_events
      |> Enum.map(fn evt ->
        note = Map.get(@drum_notes, evt["category"] || evt[:category], 37)
        time_s = evt["time_s"] || evt[:time_s] || 0.0
        tick = quantize_to_16th(time_s, sixteenth_s)
        {tick, note}
      end)
      |> Enum.sort_by(fn {tick, _} -> tick end)

    midi = build_midi_type0(events, tempo_us)

    case File.write(output_path, midi) do
      :ok -> {:ok, output_path}
      {:error, reason} -> {:error, reason}
    end
  end

  def extract(_, _, _), do: {:error, :invalid_args}

  # Private

  defp quantize_to_16th(time_s, sixteenth_s) when sixteenth_s > 0 do
    nearest_16th = round(time_s / sixteenth_s)
    nearest_16th * @ticks_per_16th
  end

  defp quantize_to_16th(_, _), do: 0

  @doc false
  def build_midi_type0(events, tempo_us) do
    # Build track data: tempo event at tick 0, then note on/off pairs
    track_data = <<
      # Tempo meta event at tick 0
      0x00,          # delta time = 0
      0xFF,          # meta event
      0x51,          # tempo
      0x03,          # length = 3 bytes
      trunc(tempo_us >>> 16) :: 8,
      trunc(tempo_us >>> 8 &&& 0xFF) :: 8,
      trunc(tempo_us &&& 0xFF) :: 8
    >>

    # Build note events sorted by tick
    # Group by tick so we can handle simultaneous hits
    events_by_tick =
      events
      |> Enum.group_by(fn {tick, _} -> tick end)

    note_data =
      events_by_tick
      |> Enum.sort_by(fn {tick, _} -> tick end)
      |> Enum.reduce({<<>>, 0}, fn {tick, tick_events}, {acc, prev_tick} ->
        delta = tick - prev_tick

        # Note OFF events (delta = 0 after note on, using note_ons_with_first_delta below)
        note_offs =
          Enum.reduce(tick_events, <<>>, fn {_, note}, off_acc ->
            off_acc <>
              encode_varlen(0) <>
              <<0x89, note :: 8, 0 :: 8>>
          end)

        new_acc =
          acc <>
            # First note on gets the full delta, subsequent simultaneous notes get 0
            note_ons_with_first_delta(tick_events, delta) <>
            note_offs

        {new_acc, tick}
      end)
      |> elem(0)

    # End of track meta event
    eot = encode_varlen(0) <> <<0xFF, 0x2F, 0x00>>

    full_track = track_data <> note_data <> eot

    # MIDI header: type 0, 1 track, ticks per quarter
    header = <<"MThd",
      0 :: 32,   # header length = 6
      0 :: 16,   # format type 0
      1 :: 16,   # 1 track
      @ticks_per_quarter :: 16
    >>

    track_length = byte_size(full_track)
    track_chunk = <<"MTrk", track_length :: 32>> <> full_track

    header <> track_chunk
  end

  # Handle simultaneous notes: first gets the real delta, subsequent get 0
  defp note_ons_with_first_delta([], _), do: <<>>

  defp note_ons_with_first_delta(tick_events, delta) do
    [{_, first_note} | rest] = tick_events

    first = encode_varlen(delta) <> <<0x99, first_note :: 8, 100 :: 8>>

    others =
      Enum.reduce(rest, <<>>, fn {_, note}, acc ->
        acc <> encode_varlen(0) <> <<0x99, note :: 8, 100 :: 8>>
      end)

    first <> others <>
      Enum.reduce(tick_events, <<>>, fn {_, note}, acc ->
        acc <> encode_varlen(0) <> <<0x89, note :: 8, 0 :: 8>>
      end)
  end

  # Variable-length encoding for MIDI delta times
  defp encode_varlen(value) when value < 128 do
    <<value :: 8>>
  end

  defp encode_varlen(value) do
    encode_varlen_bytes(value, [])
  end

  defp encode_varlen_bytes(0, []), do: <<0>>

  defp encode_varlen_bytes(0, acc) do
    [first | rest] = acc
    rest_bytes = Enum.reduce(rest, <<>>, fn b, acc_bin -> acc_bin <> <<b ||| 0x80 :: 8>> end)
    <<first :: 8>> <> rest_bytes
  end

  defp encode_varlen_bytes(value, acc) do
    encode_varlen_bytes(value >>> 7, [value &&& 0x7F | acc])
  end
end
