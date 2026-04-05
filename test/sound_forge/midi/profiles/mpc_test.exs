defmodule SoundForge.MIDI.Profiles.MPCTest do
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.Profiles.MPC

  describe "detect/1" do
    test "detects MPC One" do
      assert {:ok, :mpc_one} = MPC.detect("Akai MPC One")
      assert {:ok, :mpc_one} = MPC.detect("MPC ONE MIDI Port")
    end

    test "detects MPC Live" do
      assert {:ok, :mpc_live} = MPC.detect("Akai MPC Live")
      assert {:ok, :mpc_live} = MPC.detect("MPC Live II")
    end

    test "detects MPC Studio Mk2" do
      assert {:ok, :mpc_studio_mk2} = MPC.detect("MPC Studio Mk2 MIDI")
      assert {:ok, :mpc_studio_mk2} = MPC.detect("Akai MPC Studio")
    end

    test "detects MPC Key" do
      assert {:ok, :mpc_key} = MPC.detect("Akai MPC Key")
    end

    test "returns :unknown for non-MPC device" do
      assert :unknown = MPC.detect("Arturia KeyLab")
      assert :unknown = MPC.detect("Some Controller")
    end

    test "detection is case-insensitive" do
      assert {:ok, :mpc_one} = MPC.detect("akai mpc one")
      assert {:ok, :mpc_live} = MPC.detect("AKAI MPC LIVE")
    end
  end

  describe "pad_color/3" do
    test "returns sysex bytes for MPC One red" do
      result = MPC.pad_color(:mpc_one, 0, :red)
      assert is_list(result)
      assert hd(result) == 0xF0
      assert List.last(result) == 0xF7
      # Device ID for MPC One is 0x40
      assert Enum.at(result, 3) == 0x40
      # Pad number
      assert Enum.at(result, 7) == 0
      # Red = {127, 0, 0}
      assert Enum.at(result, 8) == 127
      assert Enum.at(result, 9) == 0
      assert Enum.at(result, 10) == 0
    end

    test "returns sysex bytes for MPC Live green pad 5" do
      result = MPC.pad_color(:mpc_live, 5, :green)
      # Device ID for MPC Live is 0x3A
      assert Enum.at(result, 3) == 0x3A
      assert Enum.at(result, 7) == 5
      # Green = {0, 127, 0}
      assert Enum.at(result, 8) == 0
      assert Enum.at(result, 9) == 127
    end

    test "returns off color (all zeros)" do
      result = MPC.pad_color(:mpc_one, 0, :off)
      assert Enum.at(result, 8) == 0
      assert Enum.at(result, 9) == 0
      assert Enum.at(result, 10) == 0
    end
  end

  describe "default_mappings/2" do
    test "returns 23 mappings (16 pads + 4 Q-Links + 3 transport)" do
      mappings = MPC.default_mappings(:mpc_one, 1)
      assert length(mappings) == 23
    end

    test "pad mappings use note_on type" do
      mappings = MPC.default_mappings(:mpc_one, 1)
      pad_mappings = Enum.filter(mappings, &(&1.action == :stem_solo))
      assert length(pad_mappings) == 16
      assert Enum.all?(pad_mappings, &(&1.midi_type == :note_on))
    end

    test "Q-Link mappings use CC type" do
      mappings = MPC.default_mappings(:mpc_one, 1)
      vol_mappings = Enum.filter(mappings, &(&1.action == :stem_volume))
      assert length(vol_mappings) == 4
      assert Enum.all?(vol_mappings, &(&1.midi_type == :cc))
    end

    test "transport mappings include play, stop, bpm_tap" do
      mappings = MPC.default_mappings(:mpc_one, 1)
      transport_actions = mappings |> Enum.map(& &1.action) |> Enum.filter(&(&1 in [:play, :stop, :bpm_tap]))
      assert length(transport_actions) == 3
    end

    test "MPC Studio Mk2 uses different Q-Link CCs" do
      mappings = MPC.default_mappings(:mpc_studio_mk2, 1)
      vol_mappings = Enum.filter(mappings, &(&1.action == :stem_volume))
      cc_numbers = Enum.map(vol_mappings, & &1.number) |> Enum.sort()
      assert cc_numbers == [20, 21, 22, 23]
    end

    test "all mappings include user_id" do
      mappings = MPC.default_mappings(:mpc_one, 42)
      assert Enum.all?(mappings, &(&1.user_id == 42))
    end
  end

  describe "supported_models/0" do
    test "returns list of model atoms" do
      models = MPC.supported_models()
      assert :mpc_one in models
      assert :mpc_live in models
      assert :mpc_studio_mk2 in models
      assert :mpc_key in models
    end
  end

  describe "model_name/1" do
    test "returns human-readable names" do
      assert MPC.model_name(:mpc_one) == "MPC One"
      assert MPC.model_name(:mpc_live) == "MPC Live"
    end
  end

  describe "pad_notes/0" do
    test "returns 16 notes from 36 to 51" do
      notes = MPC.pad_notes()
      assert length(notes) == 16
      assert hd(notes) == 36
      assert List.last(notes) == 51
    end
  end
end
