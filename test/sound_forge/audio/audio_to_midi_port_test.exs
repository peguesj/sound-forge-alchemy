defmodule SoundForge.Audio.AudioToMidiPortTest do
  use ExUnit.Case, async: true

  alias SoundForge.Audio.AudioToMidiPort

  describe "start_link/1" do
    test "starts the GenServer" do
      assert {:ok, pid} = AudioToMidiPort.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with a name" do
      assert {:ok, pid} = AudioToMidiPort.start_link(name: :test_midi_port)
      assert Process.alive?(pid)
      assert Process.whereis(:test_midi_port) == pid
      GenServer.stop(pid)
    end
  end

  describe "convert/2" do
    test "returns error for nonexistent file" do
      {:ok, pid} = AudioToMidiPort.start_link([])

      result = AudioToMidiPort.convert("/nonexistent/file.mp3", server: pid)

      # Port will exit with non-zero since file doesn't exist
      assert {:error, _reason} = result
    end
  end
end
