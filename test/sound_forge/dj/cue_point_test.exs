defmodule SoundForge.DJ.CuePointTest do
  use ExUnit.Case, async: true

  alias SoundForge.DJ.CuePoint

  @valid_attrs %{
    track_id: Ecto.UUID.generate(),
    user_id: 1,
    position_ms: 30_000,
    cue_type: :hot
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = CuePoint.changeset(%CuePoint{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires track_id" do
      changeset = CuePoint.changeset(%CuePoint{}, Map.delete(@valid_attrs, :track_id))
      refute changeset.valid?
    end

    test "requires user_id" do
      changeset = CuePoint.changeset(%CuePoint{}, Map.delete(@valid_attrs, :user_id))
      refute changeset.valid?
    end

    test "requires position_ms" do
      changeset = CuePoint.changeset(%CuePoint{}, Map.delete(@valid_attrs, :position_ms))
      refute changeset.valid?
    end

    test "requires cue_type" do
      changeset = CuePoint.changeset(%CuePoint{}, Map.delete(@valid_attrs, :cue_type))
      refute changeset.valid?
    end

    test "validates position_ms non-negative" do
      changeset = CuePoint.changeset(%CuePoint{}, %{@valid_attrs | position_ms: -1})
      refute changeset.valid?

      changeset = CuePoint.changeset(%CuePoint{}, %{@valid_attrs | position_ms: 0})
      assert changeset.valid?
    end

    test "validates all cue types" do
      for type <- [:hot, :loop_in, :loop_out, :memory] do
        changeset = CuePoint.changeset(%CuePoint{}, %{@valid_attrs | cue_type: type})
        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end

    test "validates color format" do
      valid = CuePoint.changeset(%CuePoint{}, Map.put(@valid_attrs, :color, "#FF0000"))
      assert valid.valid?

      invalid = CuePoint.changeset(%CuePoint{}, Map.put(@valid_attrs, :color, "red"))
      refute invalid.valid?

      invalid2 = CuePoint.changeset(%CuePoint{}, Map.put(@valid_attrs, :color, "#GGG"))
      refute invalid2.valid?
    end

    test "validates label max length" do
      long_label = String.duplicate("a", 101)
      changeset = CuePoint.changeset(%CuePoint{}, Map.put(@valid_attrs, :label, long_label))
      refute changeset.valid?

      ok_label = String.duplicate("a", 100)
      changeset = CuePoint.changeset(%CuePoint{}, Map.put(@valid_attrs, :label, ok_label))
      assert changeset.valid?
    end

    test "validates confidence range 0.0 to 1.0" do
      too_low = CuePoint.changeset(%CuePoint{}, Map.put(@valid_attrs, :confidence, -0.1))
      refute too_low.valid?

      too_high = CuePoint.changeset(%CuePoint{}, Map.put(@valid_attrs, :confidence, 1.1))
      refute too_high.valid?

      valid_low = CuePoint.changeset(%CuePoint{}, Map.put(@valid_attrs, :confidence, 0.0))
      assert valid_low.valid?

      valid_high = CuePoint.changeset(%CuePoint{}, Map.put(@valid_attrs, :confidence, 1.0))
      assert valid_high.valid?
    end

    test "auto_generated defaults to false" do
      cp = %CuePoint{}
      assert cp.auto_generated == false
    end

    test "label and color are optional" do
      changeset = CuePoint.changeset(%CuePoint{}, @valid_attrs)
      assert changeset.valid?
      assert is_nil(Ecto.Changeset.get_field(changeset, :label))
      assert is_nil(Ecto.Changeset.get_field(changeset, :color))
    end
  end

  describe "cue_types/0" do
    test "returns 4 cue types" do
      types = CuePoint.cue_types()
      assert length(types) == 4
      assert :hot in types
      assert :loop_in in types
      assert :loop_out in types
      assert :memory in types
    end
  end
end
