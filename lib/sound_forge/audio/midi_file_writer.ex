defmodule SoundForge.Audio.MidiFileWriter do
  @moduledoc """
  Pure Elixir MIDI file writer.
  Generates a standard Type 1 MIDI file (.mid) from note data.
  """

  import Bitwise

  @ticks_per_beat 480

  @doc """
  Builds a MIDI file binary from a list of note maps.

  Each note map must have: `note` (int), `onset` (float seconds),
  `offset` (float seconds), `velocity` (float 0-1).

  Returns `{:ok, binary}` or `{:error, reason}`.
  """
  def build(notes, opts \\ []) when is_list(notes) do
    tempo = Keyword.get(opts, :tempo, 120)
    track_name = Keyword.get(opts, :track_name, "Piano")

    tempo_track = build_tempo_track(tempo)
    note_track = build_note_track(notes, tempo, track_name)

    header = build_header(2)
    {:ok, header <> tempo_track <> note_track}
  end

  # MIDI Header: MThd, length=6, format=1, ntracks, ticks_per_beat
  defp build_header(num_tracks) do
    "MThd" <>
      <<6::32>> <>
      <<1::16>> <>
      <<num_tracks::16>> <>
      <<@ticks_per_beat::16>>
  end

  # Tempo track: just a tempo meta event
  defp build_tempo_track(bpm) do
    microseconds_per_beat = round(60_000_000 / bpm)

    events =
      <<0>> <>
        <<0xFF, 0x51, 0x03>> <>
        <<microseconds_per_beat::24>> <>
        <<0>> <>
        <<0xFF, 0x2F, 0x00>>

    "MTrk" <> <<byte_size(events)::32>> <> events
  end

  # Note track with note on/off events
  defp build_note_track(notes, tempo, track_name) do
    # Track name meta event
    name_bytes = track_name |> String.to_charlist() |> :binary.list_to_bin()

    name_event =
      <<0>> <>
        <<0xFF, 0x03>> <>
        variable_length(byte_size(name_bytes)) <>
        name_bytes

    # Convert notes to timed events
    timed_events =
      notes
      |> Enum.flat_map(fn note ->
        onset_ticks = seconds_to_ticks(note["onset"] || note[:onset], tempo)
        offset_ticks = seconds_to_ticks(note["offset"] || note[:offset], tempo)
        midi_note = note["note"] || note[:note]
        vel = round(min(1.0, max(0.0, note["velocity"] || note[:velocity] || 0.8)) * 127)

        [
          {onset_ticks, <<0x90, midi_note, vel>>},
          {offset_ticks, <<0x80, midi_note, 0>>}
        ]
      end)
      |> Enum.sort_by(fn {tick, _} -> tick end)

    # Convert absolute ticks to delta ticks
    {midi_events, _} =
      Enum.map_reduce(timed_events, 0, fn {abs_tick, data}, prev_tick ->
        delta = max(0, abs_tick - prev_tick)
        {variable_length(delta) <> data, abs_tick}
      end)

    events_bin = IO.iodata_to_binary(midi_events)

    # End of track
    eot = <<0, 0xFF, 0x2F, 0x00>>

    track_data = name_event <> events_bin <> eot
    "MTrk" <> <<byte_size(track_data)::32>> <> track_data
  end

  defp seconds_to_ticks(seconds, tempo) do
    beats = seconds * tempo / 60.0
    round(beats * @ticks_per_beat)
  end

  # Variable-length quantity encoding (MIDI standard)
  defp variable_length(value) when value < 0x80 do
    <<value>>
  end

  defp variable_length(value) do
    do_vlq(value, <<value &&& 0x7F>>)
  end

  defp do_vlq(value, acc) when value < 0x80, do: acc

  defp do_vlq(value, acc) do
    shifted = value >>> 7
    byte = (shifted &&& 0x7F) ||| 0x80
    do_vlq(shifted, <<byte>> <> acc)
  end
end
