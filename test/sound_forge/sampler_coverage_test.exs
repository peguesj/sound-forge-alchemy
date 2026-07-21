defmodule SoundForge.SamplerCoverageTest do
  @moduledoc "Tests for Sampler context: banks, pads, stem assignment, helpers."
  use SoundForge.DataCase

  alias SoundForge.Sampler
  import SoundForge.MusicFixtures

  setup do
    user = SoundForge.AccountsFixtures.user_fixture()
    %{user: user}
  end

  describe "create_bank/1" do
    test "creates a bank with 16 pads", %{user: user} do
      assert {:ok, bank} =
               Sampler.create_bank(%{name: "Test Bank", user_id: user.id, position: 0})

      assert bank.name == "Test Bank"
      assert length(bank.pads) == 16
    end
  end

  describe "list_banks/1" do
    test "returns empty list for user with no banks", %{user: user} do
      assert Sampler.list_banks(user.id) == []
    end

    test "returns banks ordered by position", %{user: user} do
      {:ok, _b1} = Sampler.create_bank(%{name: "Bank A", user_id: user.id, position: 1})
      {:ok, _b2} = Sampler.create_bank(%{name: "Bank B", user_id: user.id, position: 0})

      banks = Sampler.list_banks(user.id)
      assert length(banks) == 2
      assert hd(banks).name == "Bank B"
    end
  end

  describe "get_bank!/1" do
    test "retrieves bank with pads preloaded", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Get Test", user_id: user.id, position: 0})
      fetched = Sampler.get_bank!(bank.id)
      assert fetched.name == "Get Test"
      assert length(fetched.pads) == 16
    end
  end

  describe "update_bank/2" do
    test "updates bank name", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Old Name", user_id: user.id, position: 0})
      assert {:ok, updated} = Sampler.update_bank(bank, %{name: "New Name"})
      assert updated.name == "New Name"
    end
  end

  describe "delete_bank/1" do
    test "deletes bank", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Delete Me", user_id: user.id, position: 0})
      assert {:ok, _} = Sampler.delete_bank(bank)
      assert Sampler.list_banks(user.id) == []
    end
  end

  describe "get_pad!/1" do
    test "retrieves a pad", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Pad Test", user_id: user.id, position: 0})
      pad = hd(bank.pads)
      fetched = Sampler.get_pad!(pad.id)
      assert fetched.index == pad.index
    end
  end

  describe "assign_stem_to_pad/2" do
    test "assigns and clears stem", %{user: user} do
      track =
        track_fixture(%{user_id: user.id, title: "Stem Track", artist: "Test", duration: 100})

      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

      stem =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: pj.id,
          stem_type: :vocals,
          file_path: "stems/v.wav",
          file_size: 1024
        })

      {:ok, bank} = Sampler.create_bank(%{name: "Assign Test", user_id: user.id, position: 0})
      pad = hd(bank.pads)

      assert {:ok, updated_pad} = Sampler.assign_stem_to_pad(pad, stem.id)
      assert updated_pad.stem_id == stem.id

      assert {:ok, cleared_pad} = Sampler.assign_stem_to_pad(updated_pad, nil)
      assert is_nil(cleared_pad.stem_id)
    end
  end

  describe "update_pad/2" do
    test "updates pad settings", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Update Pad Test", user_id: user.id, position: 0})
      pad = hd(bank.pads)

      assert {:ok, updated} = Sampler.update_pad(pad, %{label: "Kick", volume: 0.8, pitch: 2.0})
      assert updated.label == "Kick"
      assert updated.volume == 0.8
    end
  end

  describe "clear_pad/1" do
    test "resets pad to defaults", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Clear Test", user_id: user.id, position: 0})
      pad = hd(bank.pads)
      {:ok, updated} = Sampler.update_pad(pad, %{label: "Something", volume: 0.5})
      {:ok, cleared} = Sampler.clear_pad(updated)
      assert is_nil(cleared.label)
      assert cleared.volume == 1.0
    end
  end

  describe "quick_load_stems/2" do
    test "loads stems into consecutive pads", %{user: user} do
      track =
        track_fixture(%{user_id: user.id, title: "Quick Load", artist: "Test", duration: 100})

      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

      stems =
        for type <- [:vocals, :drums, :bass, :other] do
          stem_fixture(%{
            track_id: track.id,
            processing_job_id: pj.id,
            stem_type: type,
            file_path: "stems/#{type}.wav",
            file_size: 1024
          })
        end

      {:ok, bank} = Sampler.create_bank(%{name: "Quick Load Test", user_id: user.id, position: 0})
      {:ok, loaded_bank} = Sampler.quick_load_stems(bank, stems)

      assert Enum.at(loaded_bank.pads, 0).label == "Vocals"
      assert Enum.at(loaded_bank.pads, 1).label == "Drums"
      assert Enum.at(loaded_bank.pads, 2).label == "Bass"
      assert Enum.at(loaded_bank.pads, 3).label == "Other"
    end
  end

  describe "stem_type_color/1" do
    test "returns color for known stem types" do
      assert Sampler.stem_type_color(:vocals) == "#3b82f6"
      assert Sampler.stem_type_color(:drums) == "#ef4444"
      assert Sampler.stem_type_color(:bass) == "#22c55e"
      assert Sampler.stem_type_color(:other) == "#a855f7"
    end

    test "returns default for unknown atom" do
      assert Sampler.stem_type_color(:unknown_type) == "#6b7280"
    end

    test "works with string types" do
      assert Sampler.stem_type_color("vocals") == "#3b82f6"
      assert Sampler.stem_type_color("drums") == "#ef4444"
      assert Sampler.stem_type_color("bass") == "#22c55e"
      assert Sampler.stem_type_color("other") == "#a855f7"
    end

    test "returns colors for all extended stem types" do
      assert Sampler.stem_type_color(:guitar) == "#f97316"
      assert Sampler.stem_type_color(:piano) == "#eab308"
      assert Sampler.stem_type_color(:electric_guitar) == "#f97316"
      assert Sampler.stem_type_color(:acoustic_guitar) == "#92400e"
      assert Sampler.stem_type_color(:synth) == "#ec4899"
      assert Sampler.stem_type_color(:strings) == "#8b5cf6"
      assert Sampler.stem_type_color(:wind) == "#06b6d4"
    end

    test "returns default for invalid string" do
      assert Sampler.stem_type_color("totally_not_a_real_atom_xyz") == "#6b7280"
    end

    test "returns default for nil" do
      assert Sampler.stem_type_color(nil) == "#6b7280"
    end
  end

  describe "bank_midi_mappings/2" do
    test "returns empty list when no mappings exist", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "MIDI Test", user_id: user.id, position: 0})
      assert Sampler.bank_midi_mappings(user.id, bank.id) == []
    end
  end
end
