defmodule SoundForge.MIDI.MappingTest do
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.Mapping

  @valid_attrs %{
    user_id: 1,
    device_name: "MPC Live II",
    midi_type: :cc,
    channel: 0,
    number: 118,
    action: :dj_play,
    params: %{"deck" => "1"}
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = Mapping.changeset(%Mapping{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires user_id" do
      changeset = Mapping.changeset(%Mapping{}, Map.delete(@valid_attrs, :user_id))
      refute changeset.valid?
    end

    test "requires device_name" do
      changeset = Mapping.changeset(%Mapping{}, Map.delete(@valid_attrs, :device_name))
      refute changeset.valid?
    end

    test "requires midi_type" do
      changeset = Mapping.changeset(%Mapping{}, Map.delete(@valid_attrs, :midi_type))
      refute changeset.valid?
    end

    test "requires channel" do
      changeset = Mapping.changeset(%Mapping{}, Map.delete(@valid_attrs, :channel))
      refute changeset.valid?
    end

    test "requires number" do
      changeset = Mapping.changeset(%Mapping{}, Map.delete(@valid_attrs, :number))
      refute changeset.valid?
    end

    test "requires action" do
      changeset = Mapping.changeset(%Mapping{}, Map.delete(@valid_attrs, :action))
      refute changeset.valid?
    end

    test "validates channel range 0-15" do
      too_low = Mapping.changeset(%Mapping{}, %{@valid_attrs | channel: -1})
      refute too_low.valid?

      too_high = Mapping.changeset(%Mapping{}, %{@valid_attrs | channel: 16})
      refute too_high.valid?

      edge_low = Mapping.changeset(%Mapping{}, %{@valid_attrs | channel: 0})
      assert edge_low.valid?

      edge_high = Mapping.changeset(%Mapping{}, %{@valid_attrs | channel: 15})
      assert edge_high.valid?
    end

    test "validates number range 0-127" do
      too_low = Mapping.changeset(%Mapping{}, %{@valid_attrs | number: -1})
      refute too_low.valid?

      too_high = Mapping.changeset(%Mapping{}, %{@valid_attrs | number: 128})
      refute too_high.valid?

      valid_max = Mapping.changeset(%Mapping{}, %{@valid_attrs | number: 127})
      assert valid_max.valid?
    end

    test "validates device_name length" do
      too_long = Mapping.changeset(%Mapping{}, %{@valid_attrs | device_name: String.duplicate("x", 256)})
      refute too_long.valid?

      empty = Mapping.changeset(%Mapping{}, %{@valid_attrs | device_name: ""})
      refute empty.valid?
    end

    test "accepts all valid midi_types" do
      for type <- [:cc, :note_on, :note_off] do
        changeset = Mapping.changeset(%Mapping{}, %{@valid_attrs | midi_type: type})
        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end

    test "accepts all valid actions" do
      for action <- Mapping.actions() do
        changeset = Mapping.changeset(%Mapping{}, %{@valid_attrs | action: action})
        assert changeset.valid?, "Expected #{action} to be valid"
      end
    end

    test "accepts optional params, source, bank_id, parameter_index" do
      changeset =
        Mapping.changeset(%Mapping{}, %{
          @valid_attrs
          | params: %{"slot" => "1"}
        })

      assert changeset.valid?
    end
  end

  describe "actions/0" do
    test "returns list of valid action atoms" do
      actions = Mapping.actions()
      assert is_list(actions)
      assert :dj_play in actions
      assert :stem_volume in actions
      assert :pad_trigger in actions
    end
  end

  describe "midi_types/0" do
    test "returns list of valid MIDI type atoms" do
      types = Mapping.midi_types()
      assert types == [:cc, :note_on, :note_off]
    end
  end
end
