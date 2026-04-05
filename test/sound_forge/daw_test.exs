defmodule SoundForge.DAWTest do
  use SoundForge.DataCase

  alias SoundForge.DAW

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  setup do
    user = user_fixture()
    track = track_fixture(%{user_id: user.id})
    pj = processing_job_fixture(%{track_id: track.id})
    stem = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})
    %{user: user, track: track, stem: stem}
  end

  describe "edit_operations CRUD" do
    test "create_edit_operation/1 with valid data", %{user: user, stem: stem} do
      attrs = %{
        stem_id: stem.id,
        user_id: user.id,
        operation_type: :crop,
        params: %{"start" => 0.0, "end" => 10.0},
        position: 0
      }

      assert {:ok, op} = DAW.create_edit_operation(attrs)
      assert op.operation_type == :crop
      assert op.position == 0
    end

    test "create_edit_operation/1 with invalid data returns error" do
      assert {:error, _changeset} = DAW.create_edit_operation(%{})
    end

    test "list_edit_operations/2 returns ordered operations", %{user: user, stem: stem} do
      DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :gain, params: %{}, position: 2})
      DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :crop, params: %{}, position: 0})
      DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :fade_in, params: %{}, position: 1})

      ops = DAW.list_edit_operations(stem.id, user.id)
      assert length(ops) == 3
      positions = Enum.map(ops, & &1.position)
      assert positions == [0, 1, 2]
    end

    test "list_edit_operations/2 scopes to user", %{user: user, stem: stem} do
      other_user = user_fixture()
      DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :crop, params: %{}, position: 0})
      DAW.create_edit_operation(%{stem_id: stem.id, user_id: other_user.id, operation_type: :trim, params: %{}, position: 0})

      assert length(DAW.list_edit_operations(stem.id, user.id)) == 1
      assert length(DAW.list_edit_operations(stem.id, other_user.id)) == 1
    end

    test "get_edit_operation!/1 returns operation", %{user: user, stem: stem} do
      {:ok, op} = DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :crop, params: %{}, position: 0})

      found = DAW.get_edit_operation!(op.id)
      assert found.id == op.id
    end

    test "get_edit_operation!/1 raises for nonexistent" do
      assert_raise Ecto.NoResultsError, fn ->
        DAW.get_edit_operation!(Ecto.UUID.generate())
      end
    end

    test "update_edit_operation/2 updates params", %{user: user, stem: stem} do
      {:ok, op} = DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :gain, params: %{"level" => 0.5}, position: 0})

      assert {:ok, updated} = DAW.update_edit_operation(op, %{params: %{"level" => 0.8}})
      assert updated.params == %{"level" => 0.8}
    end

    test "delete_edit_operation/1 removes operation", %{user: user, stem: stem} do
      {:ok, op} = DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :crop, params: %{}, position: 0})
      assert {:ok, _} = DAW.delete_edit_operation(op)

      assert_raise Ecto.NoResultsError, fn ->
        DAW.get_edit_operation!(op.id)
      end
    end
  end

  describe "reorder_operations/2" do
    test "reorders operations by provided ID list", %{user: user, stem: stem} do
      {:ok, op1} = DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :crop, params: %{}, position: 0})
      {:ok, op2} = DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :gain, params: %{}, position: 1})
      {:ok, op3} = DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :fade_in, params: %{}, position: 2})

      # Reverse the order
      assert {:ok, reordered} = DAW.reorder_operations(stem.id, [op3.id, op1.id, op2.id])

      positions = Enum.map(reordered, & &1.position)
      assert positions == [0, 1, 2]

      # Verify the types match the new order
      types = Enum.map(reordered, & &1.operation_type)
      assert types == [:fade_in, :crop, :gain]
    end
  end

  describe "apply_operations/1" do
    test "returns operations in position order", %{user: user, stem: stem} do
      DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :gain, params: %{}, position: 2})
      DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :crop, params: %{}, position: 0})
      DAW.create_edit_operation(%{stem_id: stem.id, user_id: user.id, operation_type: :fade_in, params: %{}, position: 1})

      ops = DAW.apply_operations(stem)
      assert length(ops) == 3
      types = Enum.map(ops, & &1.operation_type)
      assert types == [:crop, :fade_in, :gain]
    end

    test "returns empty list for stem with no operations", %{stem: stem} do
      assert DAW.apply_operations(stem) == []
    end
  end
end
