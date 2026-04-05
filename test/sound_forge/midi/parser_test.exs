defmodule SoundForge.MIDI.ParserTest do
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.Parser
  alias SoundForge.MIDI.Message

  describe "parse/1 - note messages" do
    test "parses note_on message" do
      # Note On, channel 0, note 60 (C4), velocity 100
      assert [%Message{type: :note_on, channel: 0, data: %{note: 60, velocity: 100}}] =
               Parser.parse(<<0x90, 60, 100>>)
    end

    test "parses note_on on channel 9 (drums)" do
      assert [%Message{type: :note_on, channel: 9, data: %{note: 36, velocity: 127}}] =
               Parser.parse(<<0x99, 36, 127>>)
    end

    test "parses note_off message" do
      assert [%Message{type: :note_off, channel: 0, data: %{note: 60, velocity: 64}}] =
               Parser.parse(<<0x80, 60, 64>>)
    end

    test "treats note_on with velocity 0 as note_off" do
      assert [%Message{type: :note_off, channel: 0, data: %{note: 60, velocity: 0}}] =
               Parser.parse(<<0x90, 60, 0>>)
    end

    test "parses note_off on channel 15" do
      assert [%Message{type: :note_off, channel: 15}] =
               Parser.parse(<<0x8F, 60, 64>>)
    end
  end

  describe "parse/1 - control change" do
    test "parses CC message" do
      assert [%Message{type: :cc, channel: 0, data: %{controller: 1, value: 64}}] =
               Parser.parse(<<0xB0, 1, 64>>)
    end

    test "parses CC on channel 5" do
      assert [%Message{type: :cc, channel: 5, data: %{controller: 74, value: 127}}] =
               Parser.parse(<<0xB5, 74, 127>>)
    end
  end

  describe "parse/1 - program change" do
    test "parses program change (2-byte message)" do
      assert [%Message{type: :program_change, channel: 0, data: %{program: 42}}] =
               Parser.parse(<<0xC0, 42>>)
    end
  end

  describe "parse/1 - channel pressure" do
    test "parses channel pressure (2-byte message)" do
      assert [%Message{type: :channel_pressure, channel: 0, data: %{pressure: 100}}] =
               Parser.parse(<<0xD0, 100>>)
    end
  end

  describe "parse/1 - polyphonic pressure" do
    test "parses poly pressure" do
      assert [%Message{type: :poly_pressure, channel: 0, data: %{note: 60, pressure: 80}}] =
               Parser.parse(<<0xA0, 60, 80>>)
    end
  end

  describe "parse/1 - pitch bend" do
    test "parses pitch bend (14-bit value)" do
      # LSB=0, MSB=64 => value = 64*128 + 0 = 8192 (center)
      assert [%Message{type: :pitch_bend, channel: 0, data: %{value: 8192}}] =
               Parser.parse(<<0xE0, 0, 64>>)
    end

    test "parses pitch bend minimum" do
      assert [%Message{type: :pitch_bend, channel: 0, data: %{value: 0}}] =
               Parser.parse(<<0xE0, 0, 0>>)
    end

    test "parses pitch bend maximum" do
      # LSB=127, MSB=127 => value = 127*128 + 127 = 16383
      assert [%Message{type: :pitch_bend, channel: 0, data: %{value: 16383}}] =
               Parser.parse(<<0xE0, 127, 127>>)
    end
  end

  describe "parse/1 - system real-time" do
    test "parses clock message" do
      assert [%Message{type: :clock, channel: nil}] = Parser.parse(<<0xF8>>)
    end

    test "parses start message" do
      assert [%Message{type: :start, channel: nil}] = Parser.parse(<<0xFA>>)
    end

    test "parses stop message" do
      assert [%Message{type: :stop, channel: nil}] = Parser.parse(<<0xFC>>)
    end

    test "parses continue message" do
      assert [%Message{type: :continue, channel: nil}] = Parser.parse(<<0xFB>>)
    end
  end

  describe "parse/1 - sysex" do
    test "parses sysex message with terminator" do
      assert [%Message{type: :sysex, channel: nil, data: %{payload: <<0x7E, 0x7F>>}}] =
               Parser.parse(<<0xF0, 0x7E, 0x7F, 0xF7>>)
    end

    test "handles unterminated sysex" do
      result = Parser.parse(<<0xF0, 0x01, 0x02, 0x03>>)
      assert [%Message{type: :sysex, data: %{payload: _}}] = result
    end
  end

  describe "parse/1 - multi-message streams" do
    test "parses multiple messages in one binary" do
      # Note On + Clock + Note Off
      bytes = <<0x90, 60, 100, 0xF8, 0x80, 60, 64>>
      result = Parser.parse(bytes)
      assert length(result) == 3
      assert [%Message{type: :note_on}, %Message{type: :clock}, %Message{type: :note_off}] = result
    end

    test "supports running status" do
      # Note On status 0x90, then data for two notes without repeating status
      bytes = <<0x90, 60, 100, 62, 90>>
      result = Parser.parse(bytes)
      assert length(result) == 2
      assert [%Message{type: :note_on, data: %{note: 60}}, %Message{type: :note_on, data: %{note: 62}}] = result
    end
  end

  describe "parse/1 - edge cases" do
    test "returns empty list for empty binary" do
      assert Parser.parse(<<>>) == []
    end

    test "returns empty list for non-binary input" do
      assert Parser.parse(nil) == []
      assert Parser.parse(42) == []
    end

    test "sets timestamp on all messages" do
      [msg] = Parser.parse(<<0xF8>>)
      assert is_integer(msg.timestamp)
      assert msg.timestamp != 0
    end

    test "drops incomplete channel messages" do
      # Status byte 0x90 (note on) with only one data byte
      result = Parser.parse(<<0x90, 60>>)
      assert result == []
    end
  end
end
