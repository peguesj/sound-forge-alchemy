defmodule SoundForge.SamplerTest do
  @moduledoc """
  Tests for the Sampler context: bank CRUD, pad assignments, and helpers.
  """
  use SoundForge.DataCase

  import SoundForge.MusicFixtures

  alias SoundForge.Sampler

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

    test "fails without user_id" do
      assert {:error, _} = Sampler.create_bank(%{name: "No User", position: 0})
    end
  end

  describe "list_banks/1" do
    test "returns banks for user", %{user: user} do
      {:ok, _} = Sampler.create_bank(%{name: "Bank A", user_id: user.id, position: 0})
      {:ok, _} = Sampler.create_bank(%{name: "Bank B", user_id: user.id, position: 1})

      banks = Sampler.list_banks(user.id)
      assert length(banks) >= 2
    end

    test "returns empty for user with no banks" do
      assert Sampler.list_banks(-1) == []
    end
  end

  describe "get_bank!/1" do
    test "returns bank with pads preloaded", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Get Test", user_id: user.id, position: 0})
      fetched = Sampler.get_bank!(bank.id)
      assert fetched.name == "Get Test"
      assert length(fetched.pads) == 16
    end
  end

  describe "update_bank/2" do
    test "updates bank name", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Original", user_id: user.id, position: 0})
      assert {:ok, updated} = Sampler.update_bank(bank, %{name: "Renamed"})
      assert updated.name == "Renamed"
    end
  end

  describe "delete_bank/1" do
    test "deletes a bank", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Delete Me", user_id: user.id, position: 0})
      assert {:ok, _} = Sampler.delete_bank(bank)
    end
  end

  describe "get_pad!/1" do
    test "returns pad with stem preloaded", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Pad Test", user_id: user.id, position: 0})
      pad = List.first(bank.pads)
      fetched = Sampler.get_pad!(pad.id)
      assert fetched.index == 0
    end
  end

  describe "update_pad/2" do
    test "updates pad attributes", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Pad Update", user_id: user.id, position: 0})
      pad = List.first(bank.pads)

      assert {:ok, updated} =
               Sampler.update_pad(pad, %{label: "Kick", color: "#FF0000", volume: 0.8})

      assert updated.label == "Kick"
      assert updated.color == "#FF0000"
    end
  end

  describe "clear_pad/1" do
    test "resets pad to defaults", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Clear Test", user_id: user.id, position: 0})
      pad = List.first(bank.pads)
      {:ok, pad} = Sampler.update_pad(pad, %{label: "Custom", color: "#FF0000"})

      assert {:ok, cleared} = Sampler.clear_pad(pad)
      assert cleared.label == nil
      assert cleared.color == "#6b7280"
      assert cleared.volume == 1.0
    end
  end

  describe "assign_stem_to_pad/2" do
    test "assigns and clears stem", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Assign Test", user_id: user.id, position: 0})
      pad = List.first(bank.pads)

      track = track_fixture(%{user_id: user.id, title: "T", artist: "A", duration: 120})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

      stem =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: pj.id,
          stem_type: :vocals,
          file_path: "stems/v.wav",
          file_size: 1024
        })

      assert {:ok, assigned} = Sampler.assign_stem_to_pad(pad, stem.id)
      assert assigned.stem_id == stem.id

      assert {:ok, cleared} = Sampler.assign_stem_to_pad(assigned, nil)
      assert cleared.stem_id == nil
    end
  end

  describe "quick_load_stems/2" do
    test "loads stems into consecutive pads", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "Quick Load", user_id: user.id, position: 0})
      track = track_fixture(%{user_id: user.id, title: "T", artist: "A", duration: 120})
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

      assert {:ok, loaded_bank} = Sampler.quick_load_stems(bank, stems)
      loaded_pads = Enum.take(loaded_bank.pads, 4)
      labels = Enum.map(loaded_pads, & &1.label)
      assert "Vocals" in labels
      assert "Drums" in labels
    end
  end

  describe "stem_type_color/1" do
    test "returns color for known stem types" do
      assert Sampler.stem_type_color(:vocals) == "#3b82f6"
      assert Sampler.stem_type_color(:drums) == "#ef4444"
      assert Sampler.stem_type_color(:bass) == "#22c55e"
      assert Sampler.stem_type_color(:other) == "#a855f7"
    end

    test "returns gray for unknown type" do
      assert Sampler.stem_type_color(:unknown) == "#6b7280"
    end

    test "accepts string type" do
      assert Sampler.stem_type_color("vocals") == "#3b82f6"
    end

    test "returns gray for invalid input" do
      assert Sampler.stem_type_color(123) == "#6b7280"
    end
  end

  describe "bank_midi_mappings/2" do
    test "returns empty list for bank with no mappings", %{user: user} do
      {:ok, bank} = Sampler.create_bank(%{name: "MIDI Bank", user_id: user.id, position: 0})
      assert Sampler.bank_midi_mappings(user.id, bank.id) == []
    end
  end
end
