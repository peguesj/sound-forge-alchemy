defmodule SoundForge.SamplerFullTest do
  @moduledoc """
  Comprehensive tests for the Sampler context:
  bank CRUD, pad operations, quick_load_stems, stem_type_color, bank_midi_mappings.
  """
  use SoundForge.DataCase

  alias SoundForge.Sampler

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  defp bank_attrs(user_id, overrides \\ %{}) do
    Map.merge(%{name: "Test Bank", user_id: user_id}, overrides)
  end

  describe "create_bank/1" do
    test "creates a bank with 16 pads" do
      user = user_fixture()
      assert {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      assert bank.name == "Test Bank"
      assert bank.user_id == user.id
      assert length(bank.pads) == 16
    end

    test "pads have sequential indices 0..15" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      indices = Enum.map(bank.pads, & &1.index) |> Enum.sort()
      assert indices == Enum.to_list(0..15)
    end

    test "returns error changeset with missing name" do
      assert {:error, _changeset} = Sampler.create_bank(%{user_id: nil})
    end
  end

  describe "list_banks/1" do
    test "returns empty list for user with no banks" do
      user = user_fixture()
      assert Sampler.list_banks(user.id) == []
    end

    test "returns banks ordered by position" do
      user = user_fixture()
      {:ok, _b1} = Sampler.create_bank(bank_attrs(user.id, %{position: 1, name: "B"}))
      {:ok, _b0} = Sampler.create_bank(bank_attrs(user.id, %{position: 0, name: "A"}))
      banks = Sampler.list_banks(user.id)
      assert length(banks) == 2
      assert hd(banks).name == "A"
    end

    test "does not return another user's banks" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, _} = Sampler.create_bank(bank_attrs(user1.id))
      assert Sampler.list_banks(user2.id) == []
    end
  end

  describe "get_bank!/1" do
    test "returns bank with pads preloaded" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      fetched = Sampler.get_bank!(bank.id)
      assert fetched.id == bank.id
      assert length(fetched.pads) == 16
    end

    test "raises on nonexistent ID" do
      assert_raise Ecto.NoResultsError, fn ->
        Sampler.get_bank!(Ecto.UUID.generate())
      end
    end
  end

  describe "update_bank/2" do
    test "updates bank name" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      assert {:ok, updated} = Sampler.update_bank(bank, %{name: "Renamed"})
      assert updated.name == "Renamed"
    end

    test "updates bank color and bpm" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      assert {:ok, updated} = Sampler.update_bank(bank, %{color: "#ff0000", bpm: 128.0})
      assert updated.color == "#ff0000"
      assert updated.bpm == 128.0
    end
  end

  describe "delete_bank/1" do
    test "deletes bank and cascade deletes pads" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      assert {:ok, _} = Sampler.delete_bank(bank)
      assert Sampler.list_banks(user.id) == []
    end
  end

  describe "get_pad!/1" do
    test "returns pad with stem preloaded" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      pad = hd(bank.pads)
      fetched = Sampler.get_pad!(pad.id)
      assert fetched.id == pad.id
      assert fetched.stem == nil
    end

    test "raises on nonexistent ID" do
      assert_raise Ecto.NoResultsError, fn ->
        Sampler.get_pad!(Ecto.UUID.generate())
      end
    end
  end

  describe "update_pad/2" do
    test "updates volume and pitch" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      pad = hd(bank.pads)
      assert {:ok, updated} = Sampler.update_pad(pad, %{volume: 0.5, pitch: 3.0})
      assert updated.volume == 0.5
      assert updated.pitch == 3.0
    end

    test "updates label and color" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      pad = hd(bank.pads)
      assert {:ok, updated} = Sampler.update_pad(pad, %{label: "Kick", color: "#ef4444"})
      assert updated.label == "Kick"
      assert updated.color == "#ef4444"
    end

    test "rejects invalid volume (out of range)" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      pad = hd(bank.pads)
      assert {:error, changeset} = Sampler.update_pad(pad, %{volume: 2.0})
      assert changeset.errors[:volume]
    end

    test "rejects invalid pitch (out of range)" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      pad = hd(bank.pads)
      assert {:error, changeset} = Sampler.update_pad(pad, %{pitch: 30.0})
      assert changeset.errors[:pitch]
    end
  end

  describe "clear_pad/1" do
    test "resets pad to defaults" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      pad = hd(bank.pads)
      {:ok, modified} = Sampler.update_pad(pad, %{label: "X", color: "#ff0000", volume: 0.3})
      assert {:ok, cleared} = Sampler.clear_pad(modified)
      assert cleared.label == nil
      assert cleared.color == "#6b7280"
      assert cleared.volume == 1.0
      assert cleared.pitch == 0.0
      assert cleared.velocity == 1.0
      assert cleared.start_time == 0.0
      assert cleared.end_time == nil
      assert cleared.stem_id == nil
    end
  end

  describe "assign_stem_to_pad/2" do
    test "assigns stem to pad" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, user_id: user.id})
      stem = stem_fixture(%{processing_job_id: pj.id, track_id: track.id, stem_type: :vocals})

      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      pad = hd(bank.pads)

      assert {:ok, assigned} = Sampler.assign_stem_to_pad(pad, stem.id)
      assert assigned.stem_id == stem.id
      assert assigned.stem != nil
    end

    test "clears assignment with nil" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      pad = hd(bank.pads)

      assert {:ok, cleared} = Sampler.assign_stem_to_pad(pad, nil)
      assert cleared.stem_id == nil
    end
  end

  describe "quick_load_stems/2" do
    test "assigns stems to consecutive pads" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, user_id: user.id})

      stems =
        for type <- [:vocals, :drums, :bass, :other] do
          stem_fixture(%{processing_job_id: pj.id, track_id: track.id, stem_type: type})
        end

      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      assert {:ok, loaded} = Sampler.quick_load_stems(bank, stems)

      loaded_pads = Enum.take(loaded.pads, 4)
      assert Enum.all?(loaded_pads, &(&1.stem_id != nil))
      assert Enum.at(loaded_pads, 0).label == "Vocals"
      assert Enum.at(loaded_pads, 1).label == "Drums"
    end
  end

  describe "stem_type_color/1" do
    test "known atom types return expected colors" do
      assert Sampler.stem_type_color(:vocals) == "#3b82f6"
      assert Sampler.stem_type_color(:drums) == "#ef4444"
      assert Sampler.stem_type_color(:bass) == "#22c55e"
      assert Sampler.stem_type_color(:other) == "#a855f7"
      assert Sampler.stem_type_color(:guitar) == "#f97316"
      assert Sampler.stem_type_color(:piano) == "#eab308"
      assert Sampler.stem_type_color(:synth) == "#ec4899"
    end

    test "binary stem type delegates to atom lookup" do
      assert Sampler.stem_type_color("vocals") == "#3b82f6"
      assert Sampler.stem_type_color("drums") == "#ef4444"
    end

    test "unknown atom returns gray" do
      assert Sampler.stem_type_color(:unknown_type) == "#6b7280"
    end

    test "unknown binary returns gray" do
      assert Sampler.stem_type_color("not_a_real_stem_type") == "#6b7280"
    end

    test "non-string non-atom returns gray" do
      assert Sampler.stem_type_color(42) == "#6b7280"
      assert Sampler.stem_type_color(nil) == "#6b7280"
    end
  end

  describe "bank_midi_mappings/2" do
    test "returns empty list for bank with no mappings" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      assert Sampler.bank_midi_mappings(user.id, bank.id) == []
    end
  end

  describe "import_preset/4" do
    test "returns error for invalid file content" do
      user = user_fixture()
      result = Sampler.import_preset(user.id, "not valid binary", "test.unknown")
      assert {:error, _reason} = result
    end

    test "returns error for empty binary" do
      user = user_fixture()
      result = Sampler.import_preset(user.id, <<>>, "empty.xpm")
      assert {:error, _reason} = result
    end

    test "imports valid PGM binary and creates bank with pad settings" do
      user = user_fixture()

      # Construct a minimal MPC PGM binary: 8 byte header + 1 pad entry (24 bytes)
      header = <<0, 0, 0, 0, 1, 0, 0, 0>>
      # 16 bytes sample name, null-padded
      sample_name = "kick_01" <> String.duplicate(<<0>>, 9)
      # volume=100, pan=64(center), tune=0, play_mode=0(one_shot), midi_note=36, 3 reserved
      pad_entry = sample_name <> <<100, 64, 0, 0, 36, 0, 0, 0>>
      pgm_binary = header <> pad_entry

      assert {:ok, bank} = Sampler.import_preset(user.id, pgm_binary, "test.pgm")
      assert bank.name == "MPC Legacy Program"
      assert length(bank.pads) == 16
      # First pad should have the label from preset
      first_pad = Enum.find(bank.pads, &(&1.index == 0))
      assert first_pad.label == "kick_01"
    end

    test "imports PGM with custom bank name option" do
      user = user_fixture()

      header = <<0, 0, 0, 0, 1, 0, 0, 0>>
      sample_name = "snare_01" <> String.duplicate(<<0>>, 8)
      pad_entry = sample_name <> <<80, 64, 2, 0, 38, 0, 0, 0>>
      pgm_binary = header <> pad_entry

      assert {:ok, bank} = Sampler.import_preset(user.id, pgm_binary, "test.pgm", bank_name: "My Kit")
      assert bank.name == "My Kit"
    end

    test "returns error for too-small PGM binary" do
      user = user_fixture()
      result = Sampler.import_preset(user.id, <<1, 2, 3>>, "test.pgm")
      assert {:error, _reason} = result
    end
  end

  describe "additional pad operations" do
    test "update_pad with all fields" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      pad = hd(bank.pads)

      assert {:ok, updated} =
               Sampler.update_pad(pad, %{
                 label: "Kick",
                 volume: 0.8,
                 pitch: 1.2,
                 color: "#ff0000",
                 velocity: 0.9
               })

      assert updated.label == "Kick"
      assert updated.volume == 0.8
      assert updated.pitch == 1.2
      assert updated.color == "#ff0000"
    end

    test "clear_pad resets all fields" do
      user = user_fixture()
      {:ok, bank} = Sampler.create_bank(bank_attrs(user.id))
      pad = hd(bank.pads)
      Sampler.update_pad(pad, %{label: "Custom", volume: 0.5, pitch: 2.0, color: "#ff0000"})

      assert {:ok, cleared} = Sampler.clear_pad(pad)
      assert cleared.label == nil
      assert cleared.volume == 1.0
      assert cleared.pitch == 0.0
      assert cleared.color == "#6b7280"
    end
  end

  describe "list_banks ordering" do
    test "returns banks in position order" do
      user = user_fixture()
      {:ok, b1} = Sampler.create_bank(bank_attrs(user.id, %{name: "Bank C", position: 2}))
      {:ok, b2} = Sampler.create_bank(bank_attrs(user.id, %{name: "Bank A", position: 0}))
      {:ok, b3} = Sampler.create_bank(bank_attrs(user.id, %{name: "Bank B", position: 1}))

      banks = Sampler.list_banks(user.id)
      names = Enum.map(banks, & &1.name)
      assert names == ["Bank A", "Bank B", "Bank C"]
    end
  end
end
