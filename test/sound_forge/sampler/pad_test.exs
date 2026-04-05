defmodule SoundForge.Sampler.PadTest do
  use ExUnit.Case, async: true

  alias SoundForge.Sampler.Pad

  @valid_attrs %{index: 0, bank_id: Ecto.UUID.generate()}

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = Pad.changeset(%Pad{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires index" do
      changeset = Pad.changeset(%Pad{}, Map.delete(@valid_attrs, :index))
      refute changeset.valid?
    end

    test "requires bank_id" do
      changeset = Pad.changeset(%Pad{}, Map.delete(@valid_attrs, :bank_id))
      refute changeset.valid?
    end

    test "validates index range 0-15" do
      valid_low = Pad.changeset(%Pad{}, %{@valid_attrs | index: 0})
      assert valid_low.valid?

      valid_high = Pad.changeset(%Pad{}, %{@valid_attrs | index: 15})
      assert valid_high.valid?

      too_high = Pad.changeset(%Pad{}, %{@valid_attrs | index: 16})
      refute too_high.valid?

      too_low = Pad.changeset(%Pad{}, %{@valid_attrs | index: -1})
      refute too_low.valid?
    end

    test "validates volume range 0.0-1.0" do
      valid = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :volume, 0.5))
      assert valid.valid?

      too_high = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :volume, 1.1))
      refute too_high.valid?

      too_low = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :volume, -0.1))
      refute too_low.valid?
    end

    test "validates pitch range -24.0 to 24.0" do
      valid = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :pitch, 12.0))
      assert valid.valid?

      too_high = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :pitch, 24.1))
      refute too_high.valid?

      too_low = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :pitch, -24.1))
      refute too_low.valid?
    end

    test "validates velocity range 0.0-1.0" do
      valid = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :velocity, 0.8))
      assert valid.valid?

      too_high = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :velocity, 1.1))
      refute too_high.valid?
    end

    test "validates start_time non-negative" do
      valid = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :start_time, 0.0))
      assert valid.valid?

      negative = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :start_time, -1.0))
      refute negative.valid?
    end

    test "accepts optional label" do
      changeset = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :label, "Kick"))
      assert changeset.valid?
    end

    test "accepts optional color" do
      changeset = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :color, "#ff0000"))
      assert changeset.valid?
    end

    test "accepts optional stem_id" do
      changeset = Pad.changeset(%Pad{}, Map.put(@valid_attrs, :stem_id, Ecto.UUID.generate()))
      assert changeset.valid?
    end
  end

  describe "defaults" do
    test "color defaults to gray" do
      pad = %Pad{}
      assert pad.color == "#6b7280"
    end

    test "volume defaults to 1.0" do
      pad = %Pad{}
      assert pad.volume == 1.0
    end

    test "pitch defaults to 0.0" do
      pad = %Pad{}
      assert pad.pitch == 0.0
    end

    test "velocity defaults to 1.0" do
      pad = %Pad{}
      assert pad.velocity == 1.0
    end

    test "start_time defaults to 0.0" do
      pad = %Pad{}
      assert pad.start_time == 0.0
    end
  end
end
