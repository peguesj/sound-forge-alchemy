defmodule SoundForge.MIDI.MappingsTest do
  use SoundForge.DataCase

  alias SoundForge.MIDI.Mappings
  alias SoundForge.Sampler.Bank

  import SoundForge.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  defp create_bank(user_id) do
    %Bank{}
    |> Bank.changeset(%{name: "Test Bank", user_id: user_id})
    |> Repo.insert!()
  end

  describe "list_mappings/1" do
    test "returns empty list for user with no mappings", %{user: user} do
      assert Mappings.list_mappings(user.id) == []
    end

    test "returns mappings for user", %{user: user} do
      {:ok, _} =
        Mappings.create_mapping(%{
          user_id: user.id,
          device_name: "Test Controller",
          midi_type: :cc,
          channel: 0,
          number: 1,
          action: :stem_volume,
          params: %{}
        })

      mappings = Mappings.list_mappings(user.id)
      assert length(mappings) == 1
    end
  end

  describe "create_mapping/1" do
    test "creates a mapping with valid attrs", %{user: user} do
      attrs = %{
        user_id: user.id,
        device_name: "MPC Live II",
        midi_type: :cc,
        channel: 0,
        number: 118,
        action: :dj_play,
        params: %{"deck" => "1"}
      }

      assert {:ok, mapping} = Mappings.create_mapping(attrs)
      assert mapping.device_name == "MPC Live II"
      assert mapping.action == :dj_play
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = Mappings.create_mapping(%{})
      refute changeset.valid?
    end
  end

  describe "delete_mapping/1" do
    test "deletes a mapping", %{user: user} do
      {:ok, mapping} =
        Mappings.create_mapping(%{
          user_id: user.id,
          device_name: "Test",
          midi_type: :cc,
          channel: 0,
          number: 1,
          action: :stem_volume,
          params: %{}
        })

      assert {:ok, _} = Mappings.delete_mapping(mapping)
      assert Mappings.list_mappings(user.id) == []
    end
  end

  describe "get_mappings_for_device/2" do
    test "filters by device name", %{user: user} do
      Mappings.create_mapping(%{
        user_id: user.id,
        device_name: "Device A",
        midi_type: :cc,
        channel: 0,
        number: 1,
        action: :stem_volume,
        params: %{}
      })

      Mappings.create_mapping(%{
        user_id: user.id,
        device_name: "Device B",
        midi_type: :cc,
        channel: 0,
        number: 2,
        action: :stem_mute,
        params: %{}
      })

      assert length(Mappings.get_mappings_for_device(user.id, "Device A")) == 1
      assert length(Mappings.get_mappings_for_device(user.id, "Device B")) == 1
    end
  end

  describe "default_generic_preset/1" do
    test "returns 3 default mappings", %{user: user} do
      preset = Mappings.default_generic_preset(user.id)
      assert length(preset) == 3
      assert Enum.all?(preset, &(&1.user_id == user.id))
      assert Enum.all?(preset, &(&1.device_name == "Generic MIDI Controller"))
    end
  end

  describe "insert_default_preset/1" do
    test "inserts generic preset mappings", %{user: user} do
      results = Mappings.insert_default_preset(user.id)
      assert length(results) == 3
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  describe "default_dj_preset/1" do
    test "returns 9 DJ preset mappings", %{user: user} do
      preset = Mappings.default_dj_preset(user.id)
      assert length(preset) == 9
      actions = Enum.map(preset, & &1.action)
      assert :dj_play in actions
      assert :dj_crossfader in actions
      assert :dj_pitch in actions
    end
  end

  describe "insert_dj_preset/1" do
    test "inserts DJ preset mappings", %{user: user} do
      results = Mappings.insert_dj_preset(user.id)
      assert length(results) == 9
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  describe "upsert_pad_mapping/1" do
    test "creates a new mapping when none exists", %{user: user} do
      attrs = %{
        user_id: user.id,
        device_name: "Pad Controller",
        midi_type: :note_on,
        channel: 0,
        number: 36,
        action: :pad_trigger,
        params: %{},
        source: "manual"
      }

      assert {:ok, mapping} = Mappings.upsert_pad_mapping(attrs)
      assert mapping.action == :pad_trigger
      assert mapping.number == 36
    end

    test "updates existing mapping on same key", %{user: user} do
      attrs = %{
        user_id: user.id,
        device_name: "Pad Controller",
        midi_type: :note_on,
        channel: 0,
        number: 36,
        action: :pad_trigger,
        params: %{},
        source: "manual"
      }

      {:ok, original} = Mappings.upsert_pad_mapping(attrs)

      {:ok, updated} =
        Mappings.upsert_pad_mapping(%{attrs | action: :pad_volume, params: %{"target" => "vol"}})

      assert updated.id == original.id
      assert updated.action == :pad_volume
      assert updated.params == %{"target" => "vol"}
    end

    test "does not create duplicate when upserting same key", %{user: user} do
      attrs = %{
        user_id: user.id,
        device_name: "Pad Controller",
        midi_type: :cc,
        channel: 1,
        number: 10,
        action: :pad_pitch,
        params: %{}
      }

      {:ok, _} = Mappings.upsert_pad_mapping(attrs)
      {:ok, _} = Mappings.upsert_pad_mapping(%{attrs | action: :pad_volume})

      mappings = Mappings.get_mappings_for_device(user.id, "Pad Controller")
      assert length(mappings) == 1
    end
  end

  describe "list_bank_mappings/2" do
    test "returns mappings scoped to a specific bank", %{user: user} do
      bank_a = create_bank(user.id)
      bank_b = create_bank(user.id)

      {:ok, _} =
        Mappings.create_mapping(%{
          user_id: user.id,
          device_name: "Controller",
          midi_type: :note_on,
          channel: 0,
          number: 36,
          action: :pad_trigger,
          bank_id: bank_a.id,
          parameter_index: 0
        })

      {:ok, _} =
        Mappings.create_mapping(%{
          user_id: user.id,
          device_name: "Controller",
          midi_type: :note_on,
          channel: 0,
          number: 37,
          action: :pad_trigger,
          bank_id: bank_b.id,
          parameter_index: 0
        })

      result = Mappings.list_bank_mappings(user.id, bank_a.id)
      assert length(result) == 1
      assert hd(result).bank_id == bank_a.id
    end

    test "returns empty list when no mappings exist for bank", %{user: user} do
      bank = create_bank(user.id)
      assert Mappings.list_bank_mappings(user.id, bank.id) == []
    end
  end

  describe "delete_bank_mappings/2" do
    test "deletes all mappings for a specific bank", %{user: user} do
      bank = create_bank(user.id)

      {:ok, _} =
        Mappings.create_mapping(%{
          user_id: user.id,
          device_name: "Controller",
          midi_type: :note_on,
          channel: 0,
          number: 36,
          action: :pad_trigger,
          bank_id: bank.id
        })

      {:ok, _} =
        Mappings.create_mapping(%{
          user_id: user.id,
          device_name: "Controller",
          midi_type: :note_on,
          channel: 0,
          number: 37,
          action: :pad_trigger,
          bank_id: bank.id
        })

      {count, nil} = Mappings.delete_bank_mappings(user.id, bank.id)
      assert count == 2
      assert Mappings.list_bank_mappings(user.id, bank.id) == []
    end

    test "does not delete mappings from other banks", %{user: user} do
      bank_a = create_bank(user.id)
      bank_b = create_bank(user.id)

      {:ok, _} =
        Mappings.create_mapping(%{
          user_id: user.id,
          device_name: "Controller",
          midi_type: :note_on,
          channel: 0,
          number: 36,
          action: :pad_trigger,
          bank_id: bank_a.id
        })

      {:ok, _} =
        Mappings.create_mapping(%{
          user_id: user.id,
          device_name: "Controller",
          midi_type: :note_on,
          channel: 0,
          number: 37,
          action: :pad_trigger,
          bank_id: bank_b.id
        })

      Mappings.delete_bank_mappings(user.id, bank_a.id)
      assert length(Mappings.list_bank_mappings(user.id, bank_b.id)) == 1
    end
  end

  describe "import_preset_mappings/5" do
    test "creates mappings from parsed preset data", %{user: user} do
      bank = create_bank(user.id)

      midi_mappings = [
        %{
          midi_type: :note,
          midi_channel: 0,
          midi_number: 36,
          parameter_type: :pad_trigger,
          parameter_index: 0
        },
        %{
          midi_type: :cc,
          midi_channel: 1,
          midi_number: 7,
          parameter_type: :pad_volume,
          parameter_index: 1
        }
      ]

      results =
        Mappings.import_preset_mappings(user.id, bank.id, "MPC Live", midi_mappings, "xpm")

      assert length(results) == 2
      assert Enum.all?(results, &match?({:ok, _}, &1))

      stored = Mappings.list_bank_mappings(user.id, bank.id)
      assert length(stored) == 2
    end

    test "normalizes midi types during import", %{user: user} do
      bank = create_bank(user.id)

      midi_mappings = [
        %{
          midi_type: :note,
          midi_channel: 0,
          midi_number: 40,
          parameter_type: :pad_trigger,
          parameter_index: 0
        },
        %{
          midi_type: :program_change,
          midi_channel: 0,
          midi_number: 41,
          parameter_type: :pad_volume,
          parameter_index: 1
        }
      ]

      results =
        Mappings.import_preset_mappings(user.id, bank.id, "Device", midi_mappings, "test")

      assert Enum.all?(results, &match?({:ok, _}, &1))

      stored = Mappings.list_bank_mappings(user.id, bank.id)
      types = Enum.map(stored, & &1.midi_type)
      assert :note_on in types
      assert :cc in types
    end

    test "normalizes parameter types to actions during import", %{user: user} do
      bank = create_bank(user.id)

      midi_mappings = [
        %{
          midi_type: :cc,
          midi_channel: 0,
          midi_number: 1,
          parameter_type: :master_volume,
          parameter_index: 0
        },
        %{
          midi_type: :cc,
          midi_channel: 0,
          midi_number: 2,
          parameter_type: :crossfader,
          parameter_index: 1
        }
      ]

      results =
        Mappings.import_preset_mappings(user.id, bank.id, "Device", midi_mappings, "test")

      assert Enum.all?(results, &match?({:ok, _}, &1))

      stored = Mappings.list_bank_mappings(user.id, bank.id)
      actions = Enum.map(stored, & &1.action)
      assert :pad_master_volume in actions
      assert :dj_crossfader in actions
    end
  end
end
