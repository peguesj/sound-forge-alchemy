defmodule SoundForge.MIDI.OutputCoverageTest do
  @moduledoc "Tests for MIDI Output GenServer: start_link."
  use ExUnit.Case

  alias SoundForge.MIDI.Output

  describe "start_link/1" do
    test "starts with custom name" do
      name = :"midi_output_test_#{System.unique_integer([:positive])}"
      assert {:ok, pid} = Output.start_link(name: name)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
end
