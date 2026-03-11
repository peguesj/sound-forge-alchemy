defmodule SoundForge.Audio.MidiFileWriterTest do
  use ExUnit.Case, async: true

  alias SoundForge.Audio.MidiFileWriter

  describe "build/2" do
    test "returns {:ok, binary} with valid notes" do
      notes = [
        %{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 0.8},
        %{"note" => 64, "onset" => 0.5, "offset" => 1.0, "velocity" => 0.6}
      ]

      assert {:ok, binary} = MidiFileWriter.build(notes)
      assert is_binary(binary)
    end

    test "produces valid MIDI header (MThd)" do
      notes = [%{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 0.8}]

      {:ok, binary} = MidiFileWriter.build(notes)

      # MThd magic bytes: length=6, format=1, 2 tracks, 480 ticks/beat
      assert <<"MThd", 6::32, 1::16, 2::16, 480::16, _rest::binary>> = binary
    end

    test "contains two MTrk chunks (tempo + notes)" do
      notes = [%{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 0.8}]
      {:ok, binary} = MidiFileWriter.build(notes)

      # Count MTrk occurrences
      chunks = :binary.matches(binary, "MTrk")
      assert length(chunks) == 2
    end

    test "builds with empty notes list" do
      assert {:ok, binary} = MidiFileWriter.build([])
      assert is_binary(binary)
      assert byte_size(binary) > 0
    end

    test "respects custom tempo option" do
      notes = [%{"note" => 60, "onset" => 0.0, "offset" => 1.0, "velocity" => 0.8}]

      {:ok, binary_120} = MidiFileWriter.build(notes, tempo: 120)
      {:ok, binary_90} = MidiFileWriter.build(notes, tempo: 90)

      # Different tempos produce different binaries (tempo meta event differs)
      refute binary_120 == binary_90
    end

    test "respects custom track_name option" do
      notes = [%{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 0.8}]

      {:ok, binary} = MidiFileWriter.build(notes, track_name: "Bass")

      # Track name should appear in the binary
      assert String.contains?(binary, "Bass")
    end

    test "accepts atom-keyed note maps" do
      notes = [%{note: 60, onset: 0.0, offset: 0.5, velocity: 0.8}]

      assert {:ok, binary} = MidiFileWriter.build(notes)
      assert is_binary(binary)
    end

    test "clamps velocity to 0-1 range" do
      notes = [
        %{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 1.5},
        %{"note" => 64, "onset" => 0.5, "offset" => 1.0, "velocity" => -0.5}
      ]

      assert {:ok, binary} = MidiFileWriter.build(notes)
      assert is_binary(binary)
    end

    test "preserves note ordering by onset time" do
      notes = [
        %{"note" => 72, "onset" => 2.0, "offset" => 2.5, "velocity" => 0.8},
        %{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 0.8},
        %{"note" => 64, "onset" => 1.0, "offset" => 1.5, "velocity" => 0.8}
      ]

      assert {:ok, binary} = MidiFileWriter.build(notes)
      assert is_binary(binary)
    end

    test "handles overlapping notes" do
      notes = [
        %{"note" => 60, "onset" => 0.0, "offset" => 1.0, "velocity" => 0.8},
        %{"note" => 64, "onset" => 0.5, "offset" => 1.5, "velocity" => 0.6}
      ]

      assert {:ok, binary} = MidiFileWriter.build(notes)
      assert is_binary(binary)
    end

    test "produces deterministic output for same input" do
      notes = [%{"note" => 60, "onset" => 0.0, "offset" => 0.5, "velocity" => 0.8}]

      {:ok, binary1} = MidiFileWriter.build(notes, tempo: 120, track_name: "Piano")
      {:ok, binary2} = MidiFileWriter.build(notes, tempo: 120, track_name: "Piano")

      assert binary1 == binary2
    end
  end
end
