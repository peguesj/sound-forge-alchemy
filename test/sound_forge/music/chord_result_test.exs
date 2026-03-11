defmodule SoundForge.Music.ChordResultTest do
  use SoundForge.DataCase

  alias SoundForge.Music.ChordResult

  import SoundForge.MusicFixtures

  describe "changeset/2" do
    test "valid attributes" do
      track = track_fixture()

      changeset =
        ChordResult.changeset(%ChordResult{}, %{
          track_id: track.id,
          chords: [%{"chord" => "C", "start" => 0.0, "end" => 2.0}],
          key: "C major"
        })

      assert changeset.valid?
    end

    test "requires track_id" do
      changeset =
        ChordResult.changeset(%ChordResult{}, %{
          chords: [%{"chord" => "C", "start" => 0.0, "end" => 2.0}]
        })

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:track_id]
    end

    test "requires chords" do
      track = track_fixture()
      changeset = ChordResult.changeset(%ChordResult{}, %{track_id: track.id})
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:chords]
    end

    test "key is optional" do
      track = track_fixture()

      changeset =
        ChordResult.changeset(%ChordResult{}, %{
          track_id: track.id,
          chords: [%{"chord" => "Am", "start" => 0.0, "end" => 2.0}]
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :key) == nil
    end

    test "accepts empty chords list" do
      track = track_fixture()

      changeset =
        ChordResult.changeset(%ChordResult{}, %{
          track_id: track.id,
          chords: []
        })

      assert changeset.valid?
    end
  end

  describe "upsert_chord_result/1" do
    test "creates a new chord result" do
      track = track_fixture()

      chords = [
        %{"chord" => "C", "start" => 0.0, "end" => 2.0, "confidence" => 0.9},
        %{"chord" => "G", "start" => 2.0, "end" => 4.0, "confidence" => 0.85}
      ]

      assert {:ok, chord_result} =
               SoundForge.Music.upsert_chord_result(%{
                 track_id: track.id,
                 chords: chords,
                 key: "C major"
               })

      assert chord_result.track_id == track.id
      assert chord_result.key == "C major"
      assert length(chord_result.chords) == 2
    end

    test "updates existing chord result for same track" do
      track = track_fixture()

      chords1 = [%{"chord" => "C", "start" => 0.0, "end" => 2.0}]
      chords2 = [%{"chord" => "Am", "start" => 0.0, "end" => 4.0}]

      {:ok, first} =
        SoundForge.Music.upsert_chord_result(%{
          track_id: track.id,
          chords: chords1,
          key: "C major"
        })

      {:ok, second} =
        SoundForge.Music.upsert_chord_result(%{
          track_id: track.id,
          chords: chords2,
          key: "A minor"
        })

      assert first.id == second.id
      assert second.key == "A minor"
      assert second.chords == chords2
    end

    test "get_chord_result_for_track/1 returns nil when no result exists" do
      track = track_fixture()
      assert SoundForge.Music.get_chord_result_for_track(track.id) == nil
    end

    test "get_chord_result_for_track/1 returns existing result" do
      track = track_fixture()

      {:ok, _} =
        SoundForge.Music.upsert_chord_result(%{
          track_id: track.id,
          chords: [%{"chord" => "C", "start" => 0.0, "end" => 2.0}],
          key: "C major"
        })

      result = SoundForge.Music.get_chord_result_for_track(track.id)
      assert result != nil
      assert result.key == "C major"
    end
  end
end
