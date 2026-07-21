defmodule SoundForge.SamplerExtendedTest do
  @moduledoc """
  Extended tests for the Sampler context: bank CRUD, pad operations,
  stem assignment, quick load, and pure helper functions.
  """
  use SoundForge.DataCase

  alias SoundForge.Sampler

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "stem_type_color/1" do
    test "returns correct color for atom types" do
      assert Sampler.stem_type_color(:vocals) == "#3b82f6"
      assert Sampler.stem_type_color(:drums) == "#ef4444"
      assert Sampler.stem_type_color(:bass) == "#22c55e"
      assert Sampler.stem_type_color(:other) == "#a855f7"
    end

    test "returns correct color for string types" do
      assert Sampler.stem_type_color("vocals") == "#3b82f6"
      assert Sampler.stem_type_color("drums") == "#ef4444"
      assert Sampler.stem_type_color("bass") == "#22c55e"
    end

    test "returns default color for unknown atom" do
      assert Sampler.stem_type_color(:nonexistent_stem) == "#6b7280"
    end

    test "returns default color for unknown string" do
      assert Sampler.stem_type_color("zzz_not_a_stem") == "#6b7280"
    end

    test "returns default color for nil" do
      assert Sampler.stem_type_color(nil) == "#6b7280"
    end

    test "returns default color for integer" do
      assert Sampler.stem_type_color(42) == "#6b7280"
    end
  end

  describe "create_bank/1" do
    test "creates bank with 16 pads", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Test Bank", user_id: user.id, position: 0})
      assert bank.name == "Test Bank"
      assert length(bank.pads) == 16
    end

    test "pads have sequential positions", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Bank", user_id: user.id, position: 0})
      indices = Enum.map(bank.pads, & &1.index) |> Enum.sort()
      assert indices == Enum.to_list(0..15)
    end
  end

  describe "list_banks/1" do
    test "returns empty list for user with no banks", %{user: user} do
      assert Sampler.list_banks(user.id) == []
    end

    test "returns user's banks", %{user: user} do
      {:ok, _bank} = Sampler.create_bank(%{name: "Bank 1", user_id: user.id, position: 0})
      {:ok, _bank2} = Sampler.create_bank(%{name: "Bank 2", user_id: user.id, position: 1})
      banks = Sampler.list_banks(user.id)
      assert length(banks) == 2
    end

    test "does not return other users' banks", %{user: user} do
      other_user = user_fixture()

      {:ok, _bank} =
        Sampler.create_bank(%{name: "Other Bank", user_id: other_user.id, position: 0})

      assert Sampler.list_banks(user.id) == []
    end
  end

  describe "get_bank!/1" do
    test "returns bank with preloaded pads", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Get Bank", user_id: user.id, position: 0})
      fetched = Sampler.get_bank!(bank.id)
      assert fetched.name == "Get Bank"
      assert length(fetched.pads) == 16
    end
  end

  describe "update_bank/2" do
    test "updates bank name", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Old Name", user_id: user.id, position: 0})
      {:ok, updated} = Sampler.update_bank(bank, %{name: "New Name"})
      assert updated.name == "New Name"
    end
  end

  describe "delete_bank/1" do
    test "deletes bank and its pads", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Delete Me", user_id: user.id, position: 0})
      assert {:ok, _} = Sampler.delete_bank(bank)
      assert Sampler.list_banks(user.id) == []
    end
  end

  describe "get_pad!/1" do
    test "returns pad", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Pad Bank", user_id: user.id, position: 0})
      pad = hd(bank.pads)
      fetched = Sampler.get_pad!(pad.id)
      assert fetched.id == pad.id
    end
  end

  describe "update_pad/2" do
    test "updates pad label", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Update Pad", user_id: user.id, position: 0})
      pad = hd(bank.pads)
      {:ok, updated} = Sampler.update_pad(pad, %{label: "Kick"})
      assert updated.label == "Kick"
    end

    test "updates pad volume", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Vol Pad", user_id: user.id, position: 0})
      pad = hd(bank.pads)
      {:ok, updated} = Sampler.update_pad(pad, %{volume: 0.5})
      assert updated.volume == 0.5
    end
  end

  describe "clear_pad/1" do
    test "resets pad to defaults", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Clear Bank", user_id: user.id, position: 0})
      pad = hd(bank.pads)
      {:ok, updated} = Sampler.update_pad(pad, %{label: "Custom", volume: 0.5, pitch: 3})
      {:ok, cleared} = Sampler.clear_pad(updated)
      assert cleared.label == nil or cleared.label == ""
      assert cleared.volume == 1.0
      assert cleared.pitch == 0
    end
  end

  describe "assign_stem_to_pad/2" do
    test "assigns stem to pad", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Assign Bank", user_id: user.id, position: 0})
      pad = hd(bank.pads)

      track = track_fixture(%{user_id: user.id, title: "Assign Track"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

      stem =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: pj.id,
          stem_type: :vocals,
          file_path: "stems/vocals.wav",
          file_size: 1024
        })

      {:ok, updated} = Sampler.assign_stem_to_pad(pad, stem.id)
      assert updated.stem_id == stem.id
    end
  end

  describe "quick_load_stems/2" do
    test "loads stems into bank pads", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Quick Bank", user_id: user.id, position: 0})

      track = track_fixture(%{user_id: user.id, title: "Quick Track"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

      s1 =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: pj.id,
          stem_type: :vocals,
          file_path: "stems/vocals.wav",
          file_size: 1024
        })

      s2 =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: pj.id,
          stem_type: :drums,
          file_path: "stems/drums.wav",
          file_size: 1024
        })

      {:ok, updated_bank} = Sampler.quick_load_stems(bank, [s1, s2])
      assigned_pads = Enum.filter(updated_bank.pads, & &1.stem_id)
      assert length(assigned_pads) >= 2
    end
  end

  describe "bank_midi_mappings/2" do
    test "returns empty list when no mappings", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "MIDI Bank", user_id: user.id, position: 0})
      mappings = Sampler.bank_midi_mappings(user.id, bank.id)
      assert mappings == []
    end
  end
end
