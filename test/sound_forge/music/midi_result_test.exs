defmodule SoundForge.Music.MidiResultTest do
  use SoundForge.DataCase

  alias SoundForge.Music.MidiResult

  import SoundForge.MusicFixtures

  describe "changeset/2" do
    test "valid attributes" do
      track = track_fixture()

      changeset =
        MidiResult.changeset(%MidiResult{}, %{
          track_id: track.id,
          notes: [%{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 0.8}]
        })

      assert changeset.valid?
    end

    test "requires track_id" do
      changeset =
        MidiResult.changeset(%MidiResult{}, %{
          notes: [%{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 0.8}]
        })

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:track_id]
    end

    test "requires notes" do
      track = track_fixture()

      changeset = MidiResult.changeset(%MidiResult{}, %{track_id: track.id})
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:notes]
    end

    test "accepts empty notes list" do
      track = track_fixture()

      changeset =
        MidiResult.changeset(%MidiResult{}, %{
          track_id: track.id,
          notes: []
        })

      assert changeset.valid?
    end
  end

  describe "upsert_midi_result/1" do
    test "creates a new midi result" do
      track = track_fixture()

      notes = [
        %{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 0.8},
        %{"note" => 64, "onset" => 0.5, "offset" => 1.0, "velocity" => 0.6}
      ]

      assert {:ok, midi_result} =
               SoundForge.Music.upsert_midi_result(%{track_id: track.id, notes: notes})

      assert midi_result.track_id == track.id
      assert length(midi_result.notes) == 2
    end

    test "updates existing midi result for same track" do
      track = track_fixture()

      notes1 = [%{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 0.8}]
      notes2 = [%{"note" => 72, "onset" => 0.0, "offset" => 1.0, "velocity" => 0.9}]

      {:ok, first} = SoundForge.Music.upsert_midi_result(%{track_id: track.id, notes: notes1})
      {:ok, second} = SoundForge.Music.upsert_midi_result(%{track_id: track.id, notes: notes2})

      assert first.id == second.id
      assert second.notes == notes2
    end

    test "get_midi_result_for_track/1 returns nil when no result exists" do
      track = track_fixture()
      assert SoundForge.Music.get_midi_result_for_track(track.id) == nil
    end

    test "get_midi_result_for_track/1 returns existing result" do
      track = track_fixture()
      notes = [%{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 0.8}]
      {:ok, _} = SoundForge.Music.upsert_midi_result(%{track_id: track.id, notes: notes})

      result = SoundForge.Music.get_midi_result_for_track(track.id)
      assert result != nil
      assert result.track_id == track.id
    end
  end
end
