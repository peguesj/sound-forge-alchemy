defmodule SoundForge.DAW.EditOperationExpandedTest do
  use ExUnit.Case, async: true

  alias SoundForge.DAW.EditOperation

  @valid_attrs %{
    stem_id: Ecto.UUID.generate(),
    user_id: 1,
    operation_type: :crop,
    params: %{"start" => 0.0, "end" => 10.0},
    position: 0
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = EditOperation.changeset(%EditOperation{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires stem_id" do
      changeset = EditOperation.changeset(%EditOperation{}, Map.delete(@valid_attrs, :stem_id))
      refute changeset.valid?
    end

    test "requires user_id" do
      changeset = EditOperation.changeset(%EditOperation{}, Map.delete(@valid_attrs, :user_id))
      refute changeset.valid?
    end

    test "requires operation_type" do
      changeset = EditOperation.changeset(%EditOperation{}, Map.delete(@valid_attrs, :operation_type))
      refute changeset.valid?
    end

    test "params defaults to empty map when omitted" do
      changeset = EditOperation.changeset(%EditOperation{}, Map.delete(@valid_attrs, :params))
      # params has default: %{} so changeset is valid even without it
      assert changeset.valid?
    end

    test "rejects nil params" do
      changeset = EditOperation.changeset(%EditOperation{}, %{@valid_attrs | params: nil})
      refute changeset.valid?
    end

    test "requires position" do
      changeset = EditOperation.changeset(%EditOperation{}, Map.delete(@valid_attrs, :position))
      refute changeset.valid?
    end

    test "validates all operation types" do
      for type <- [:crop, :trim, :fade_in, :fade_out, :split, :gain] do
        changeset = EditOperation.changeset(%EditOperation{}, %{@valid_attrs | operation_type: type})
        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end

    test "validates position non-negative" do
      negative = EditOperation.changeset(%EditOperation{}, %{@valid_attrs | position: -1})
      refute negative.valid?

      zero = EditOperation.changeset(%EditOperation{}, %{@valid_attrs | position: 0})
      assert zero.valid?
    end
  end

  describe "operation_types/0" do
    test "returns 6 operation types" do
      types = EditOperation.operation_types()
      assert length(types) == 6
      assert :crop in types
      assert :trim in types
      assert :fade_in in types
      assert :fade_out in types
      assert :split in types
      assert :gain in types
    end
  end

  describe "defaults" do
    test "params defaults to empty map" do
      op = %EditOperation{}
      assert op.params == %{}
    end
  end
end
