defmodule SoundForge.MIDI.MidiExport do
  @moduledoc """
  Merges auto-detected MIDI notes with user-drawn piano roll edits and
  produces a standard MIDI file binary via MidiFileWriter.

  Auto-detected notes from the analysis pipeline use keys `onset`/`offset`
  (atom or string). User note edits from `midi_note_edits` use `onset_sec`
  and `duration_sec` and are normalised before merging.
  """

  alias SoundForge.Music
  alias SoundForge.MIDI.NoteEdits
  alias SoundForge.Audio.MidiFileWriter

  @doc """
  Builds a merged MIDI binary for a track.

  Returns `{:ok, binary}` or `{:error, :no_midi | :not_found}`.
  """
  @spec build(binary(), term(), keyword()) :: {:ok, binary()} | {:error, atom()}
  def build(track_id, user_id, opts \\ []) do
    with {:ok, track} <- Music.get_track(track_id),
         midi_result when not is_nil(midi_result) <- Music.get_midi_result_for_track(track_id) do
      auto_notes = midi_result.notes || []
      user_edits = NoteEdits.list_note_edits(track_id, user_id)

      user_notes =
        Enum.map(user_edits, fn n ->
          %{
            "note" => n.note,
            "onset" => n.onset_sec,
            "offset" => n.onset_sec + n.duration_sec,
            "velocity" => n.velocity
          }
        end)

      all_notes = auto_notes ++ user_notes
      track_name = Keyword.get(opts, :track_name, track.title || "Piano")
      MidiFileWriter.build(all_notes, track_name: track_name)
    else
      {:error, _} -> {:error, :not_found}
      nil -> {:error, :no_midi}
    end
  end
end
