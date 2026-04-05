defmodule SoundForge.SamplerContextTest do
  @moduledoc """
  Tests for the Sampler context: bank CRUD, pad operations,
  stem assignment, quick_load, stem_type_color.
  """
  use SoundForge.DataCase

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  alias SoundForge.Sampler

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "create_bank/1" do
    test "creates bank with 16 pads", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "My Bank", user_id: user.id, position: 0})
      assert bank.name == "My Bank"
      assert length(bank.pads) == 16
    end

    test "pads are indexed 0-15", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Indexed", user_id: user.id, position: 0})
      indices = Enum.map(bank.pads, & &1.index) |> Enum.sort()
      assert indices == Enum.to_list(0..15)
    end
  end

  describe "list_banks/1" do
    test "returns empty for user with no banks", %{user: user} do
      assert Sampler.list_banks(user.id) == []
    end

    test "returns banks ordered by position", %{user: user} do
      Sampler.create_bank(%{name: "B", user_id: user.id, position: 1})
      Sampler.create_bank(%{name: "A", user_id: user.id, position: 0})
      banks = Sampler.list_banks(user.id)
      assert length(banks) == 2
      assert hd(banks).name == "A"
    end
  end

  describe "get_bank!/1" do
    test "returns bank with pads preloaded", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Get", user_id: user.id})
      fetched = Sampler.get_bank!(bank.id)
      assert fetched.name == "Get"
      assert length(fetched.pads) == 16
    end
  end

  describe "update_bank/2" do
    test "updates bank name", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Old", user_id: user.id})
      {:ok, updated} = Sampler.update_bank(bank, %{name: "New"})
      assert updated.name == "New"
    end
  end

  describe "delete_bank/1" do
    test "deletes bank and pads", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Delete Me", user_id: user.id})
      {:ok, _} = Sampler.delete_bank(bank)
      assert Sampler.list_banks(user.id) == []
    end
  end

  describe "get_pad!/1" do
    test "returns pad with stem preloaded", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Pad Bank", user_id: user.id})
      pad = hd(bank.pads)
      fetched = Sampler.get_pad!(pad.id)
      assert fetched.index == pad.index
    end
  end

  describe "assign_stem_to_pad/2" do
    test "assigns stem to pad", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Assign", user_id: user.id})
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      pad = hd(bank.pads)
      {:ok, updated} = Sampler.assign_stem_to_pad(pad, stem.id)
      assert updated.stem_id == stem.id
    end

    test "clears stem with nil", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Clear", user_id: user.id})
      pad = hd(bank.pads)
      {:ok, cleared} = Sampler.assign_stem_to_pad(pad, nil)
      assert cleared.stem_id == nil
    end
  end

  describe "update_pad/2" do
    test "updates pad settings", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Update", user_id: user.id})
      pad = hd(bank.pads)
      {:ok, updated} = Sampler.update_pad(pad, %{label: "Kick", volume: 0.8, pitch: 2.0})
      assert updated.label == "Kick"
      assert updated.volume == 0.8
      assert updated.pitch == 2.0
    end
  end

  describe "clear_pad/1" do
    test "resets pad to defaults", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Clear Pad", user_id: user.id})
      pad = hd(bank.pads)
      {:ok, updated} = Sampler.update_pad(pad, %{label: "Test", volume: 0.5})
      {:ok, cleared} = Sampler.clear_pad(updated)
      assert cleared.label == nil
      assert cleared.volume == 1.0
      assert cleared.color == "#6b7280"
    end
  end

  describe "quick_load_stems/2" do
    test "loads stems into consecutive pads", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Quick", user_id: user.id})
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

      stems =
        for type <- [:vocals, :drums, :bass, :other] do
          stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: type})
        end

      {:ok, loaded} = Sampler.quick_load_stems(bank, stems)
      first_4 = Enum.take(loaded.pads, 4)
      labels = Enum.map(first_4, & &1.label)
      assert "Vocals" in labels
      assert "Drums" in labels
    end
  end

  describe "stem_type_color/1" do
    test "returns color for known atom types" do
      assert Sampler.stem_type_color(:vocals) == "#3b82f6"
      assert Sampler.stem_type_color(:drums) == "#ef4444"
      assert Sampler.stem_type_color(:bass) == "#22c55e"
    end

    test "returns default for unknown atom" do
      assert Sampler.stem_type_color(:unknown) == "#6b7280"
    end

    test "accepts string types" do
      assert Sampler.stem_type_color("vocals") == "#3b82f6"
    end

    test "returns default for invalid string" do
      assert Sampler.stem_type_color("nonexistent_stem_xyz") == "#6b7280"
    end

    test "returns default for non-string non-atom" do
      assert Sampler.stem_type_color(42) == "#6b7280"
    end
  end

  describe "bank_midi_mappings/2" do
    test "returns empty list when no mappings", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "MIDI", user_id: user.id})
      assert Sampler.bank_midi_mappings(user.id, bank.id) == []
    end
  end
end
