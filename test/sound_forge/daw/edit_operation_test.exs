defmodule SoundForge.DAW.EditOperationTest do
  use ExUnit.Case, async: true

  alias SoundForge.DAW.EditOperation

  @valid_attrs %{
    stem_id: Ecto.UUID.generate(),
    user_id: 1,
    operation_type: :crop,
    params: %{"start_ms" => 0, "end_ms" => 5000},
    position: 0
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = EditOperation.changeset(%EditOperation{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires stem_id" do
      attrs = Map.delete(@valid_attrs, :stem_id)
      changeset = EditOperation.changeset(%EditOperation{}, attrs)
      refute changeset.valid?
    end

    test "requires user_id" do
      attrs = Map.delete(@valid_attrs, :user_id)
      changeset = EditOperation.changeset(%EditOperation{}, attrs)
      refute changeset.valid?
    end

    test "requires operation_type" do
      attrs = Map.delete(@valid_attrs, :operation_type)
      changeset = EditOperation.changeset(%EditOperation{}, attrs)
      refute changeset.valid?
    end

    test "requires params" do
      # params has a schema default of %{}, so we need to explicitly set nil
      attrs = %{@valid_attrs | params: nil}
      changeset = EditOperation.changeset(%EditOperation{}, attrs)
      refute changeset.valid?
    end

    test "requires position" do
      attrs = Map.delete(@valid_attrs, :position)
      changeset = EditOperation.changeset(%EditOperation{}, attrs)
      refute changeset.valid?
    end

    test "validates operation_type inclusion" do
      for type <- [:crop, :trim, :fade_in, :fade_out, :split, :gain] do
        attrs = %{@valid_attrs | operation_type: type}
        changeset = EditOperation.changeset(%EditOperation{}, attrs)
        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end

    test "rejects invalid operation_type" do
      attrs = %{@valid_attrs | operation_type: :reverse}
      changeset = EditOperation.changeset(%EditOperation{}, attrs)
      refute changeset.valid?
    end

    test "validates position >= 0" do
      attrs = %{@valid_attrs | position: -1}
      changeset = EditOperation.changeset(%EditOperation{}, attrs)
      refute changeset.valid?
    end

    test "accepts position 0" do
      attrs = %{@valid_attrs | position: 0}
      changeset = EditOperation.changeset(%EditOperation{}, attrs)
      assert changeset.valid?
    end

    test "accepts various param maps" do
      params_list = [
        %{"start_ms" => 0, "end_ms" => 5000},
        %{"gain_db" => -3.0},
        %{"duration_ms" => 500},
        %{}
      ]

      for params <- params_list do
        attrs = %{@valid_attrs | params: params}
        changeset = EditOperation.changeset(%EditOperation{}, attrs)
        assert changeset.valid?
      end
    end
  end

  describe "operation_types/0" do
    test "returns all valid operation types" do
      assert EditOperation.operation_types() == [:crop, :trim, :fade_in, :fade_out, :split, :gain]
    end
  end
end
