defmodule SoundForge.MIDI.MessageTest do
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.Message

  describe "struct" do
    test "requires :type field" do
      assert_raise ArgumentError, fn ->
        struct!(Message, %{channel: 0})
      end
    end

    test "creates with all fields" do
      msg = %Message{type: :note_on, channel: 0, data: %{note: 60, velocity: 100}, timestamp: 12345}
      assert msg.type == :note_on
      assert msg.channel == 0
      assert msg.data == %{note: 60, velocity: 100}
      assert msg.timestamp == 12345
    end

    test "defaults data to empty map and timestamp to 0" do
      msg = %Message{type: :clock}
      assert msg.data == %{}
      assert msg.timestamp == 0
      assert msg.channel == nil
    end
  end
end
