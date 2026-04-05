defmodule SoundForge.MIDI.ModulesTest do
  use ExUnit.Case, async: true

  describe "MIDI.Output" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForge.MIDI.Output)
    end

    test "start_link/1 is defined" do
      assert {:start_link, 1} in SoundForge.MIDI.Output.__info__(:functions)
    end
  end

  describe "MIDI.MPCController" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForge.MIDI.MPCController)
    end

    test "start_link/1 is defined" do
      assert {:start_link, 1} in SoundForge.MIDI.MPCController.__info__(:functions)
    end
  end

  describe "MIDI.Profiles.MPCApp" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForge.MIDI.Profiles.MPCApp)
    end

    test "detect/1 is defined" do
      assert {:detect, 1} in SoundForge.MIDI.Profiles.MPCApp.__info__(:functions)
    end

    test "default_mappings/1 is defined" do
      assert {:default_mappings, 1} in SoundForge.MIDI.Profiles.MPCApp.__info__(:functions)
    end

    test "multi_mode?/1 is defined" do
      funs = SoundForge.MIDI.Profiles.MPCApp.__info__(:functions)
      assert {:multi_mode?, 1} in funs
    end

    test "multi_port_channel/1 is defined" do
      funs = SoundForge.MIDI.Profiles.MPCApp.__info__(:functions)
      assert {:multi_port_channel, 1} in funs
    end
  end
end
