defmodule SoundForge.MIDI.Profiles.MPCAppTest do
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.Profiles.MPCApp

  describe "detect/1" do
    test "detects MPC Beats" do
      assert {:ok, :mpc_beats} = MPCApp.detect("MPC Beats MIDI")
      assert {:ok, :mpc_beats} = MPCApp.detect("mpc beats")
    end

    test "detects MPC 2 Software" do
      assert {:ok, :mpc_2_software} = MPCApp.detect("MPC 2.0 Software")
      assert {:ok, :mpc_2_software} = MPCApp.detect("MPC 20 Software")
      assert {:ok, :mpc_2_software} = MPCApp.detect("MPC Software")
    end

    test "detects iMPC Pro 2" do
      assert {:ok, :impc_pro_2} = MPCApp.detect("iMPC Pro 2")
      assert {:ok, :impc_pro_2} = MPCApp.detect("iMPC")
    end

    test "returns :no_match for unknown ports" do
      assert :no_match = MPCApp.detect("Korg nanoKONTROL")
      assert :no_match = MPCApp.detect("IAC Driver")
      assert :no_match = MPCApp.detect("")
    end
  end

  describe "default_mappings/1" do
    test "returns mappings for mpc_beats" do
      mappings = MPCApp.default_mappings(:mpc_beats)
      assert is_list(mappings)
      assert length(mappings) > 0

      # Should have pad mappings (16 pads)
      pad_mappings = Enum.filter(mappings, &(&1.action == :stem_trigger))
      assert length(pad_mappings) == 16

      # Should have knob mappings (4 Q-Links)
      knob_mappings = Enum.filter(mappings, &(&1.action == :stem_volume))
      assert length(knob_mappings) == 4

      # Should have transport mappings (play, stop, rec)
      transport_mappings = Enum.filter(mappings, &(&1.action in [:play, :stop, :rec]))
      assert length(transport_mappings) == 3
    end

    test "pad mappings use channel 10" do
      mappings = MPCApp.default_mappings(:mpc_beats)
      pad_mappings = Enum.filter(mappings, &(&1.action == :stem_trigger))

      assert Enum.all?(pad_mappings, &(&1.midi_channel == 10))
    end

    test "pad notes are 36-51" do
      mappings = MPCApp.default_mappings(:mpc_beats)
      pad_mappings = Enum.filter(mappings, &(&1.action == :stem_trigger))
      notes = Enum.map(pad_mappings, & &1.midi_value) |> Enum.sort()

      assert notes == Enum.to_list(36..51)
    end

    test "knob CCs are 16-19" do
      mappings = MPCApp.default_mappings(:mpc_beats)
      knob_mappings = Enum.filter(mappings, &(&1.action == :stem_volume))
      ccs = Enum.map(knob_mappings, & &1.midi_value) |> Enum.sort()

      assert ccs == [16, 17, 18, 19]
    end

    test "transport CCs are 117, 118, 119" do
      mappings = MPCApp.default_mappings(:mpc_beats)
      transport = Enum.filter(mappings, &(&1.action in [:play, :stop, :rec]))
      ccs = Enum.map(transport, & &1.midi_value) |> Enum.sort()

      assert ccs == [117, 118, 119]
    end
  end

  describe "multi_mode?/1" do
    test "returns true for multi-port names" do
      assert MPCApp.multi_mode?("MPC Port A")
      assert MPCApp.multi_mode?("MPC Port B")
      assert MPCApp.multi_mode?("MPC Port C")
      assert MPCApp.multi_mode?("MPC Port D")
    end

    test "returns false for non-multi-port names" do
      refute MPCApp.multi_mode?("MPC Beats")
      refute MPCApp.multi_mode?("MPC Live")
      refute MPCApp.multi_mode?("IAC Driver")
    end
  end

  describe "multi_port_channel/1" do
    test "returns channel for multi-port" do
      assert {:ok, 1} = MPCApp.multi_port_channel("MPC Port A")
      assert {:ok, 2} = MPCApp.multi_port_channel("MPC Port B")
      assert {:ok, 3} = MPCApp.multi_port_channel("MPC Port C")
      assert {:ok, 4} = MPCApp.multi_port_channel("MPC Port D")
    end

    test "returns :not_multi for non-multi-port" do
      assert :not_multi = MPCApp.multi_port_channel("MPC Beats")
      assert :not_multi = MPCApp.multi_port_channel("IAC Driver")
    end
  end
end
