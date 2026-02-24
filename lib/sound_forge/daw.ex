defmodule SoundForge.DAW do
  @moduledoc """
  The DAW context.

  Manages non-destructive edit operations applied to audio stems.
  Operations are ordered by position and replayed to produce the final
  edited audio output.
  """

  import Ecto.Query, warn: false
  alias SoundForge.Repo

  alias SoundForge.DAW.EditOperation
  alias SoundForge.Music.Stem

  # Edit Operation functions

  @doc """
  Creates an edit operation.

  ## Examples

      iex> create_edit_operation(%{stem_id: stem_id, user_id: user_id, operation_type: :crop, params: %{}, position: 0})
      {:ok, %EditOperation{}}

      iex> create_edit_operation(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_edit_operation(map()) :: {:ok, EditOperation.t()} | {:error, Ecto.Changeset.t()}
  def create_edit_operation(attrs \\ %{}) do
    %EditOperation{}
    |> EditOperation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the list of edit operations for a given stem, scoped to a user,
  ordered by position ascending.

  ## Examples

      iex> list_edit_operations(stem_id, user_id)
      [%EditOperation{}, ...]

  """
  @spec list_edit_operations(binary(), term()) :: [EditOperation.t()]
  def list_edit_operations(stem_id, user_id) do
    EditOperation
    |> where([eo], eo.stem_id == ^stem_id and eo.user_id == ^user_id)
    |> order_by([eo], asc: eo.position)
    |> Repo.all()
  end

  @doc """
  Gets a single edit operation.

  Raises `Ecto.NoResultsError` if the EditOperation does not exist.

  ## Examples

      iex> get_edit_operation!(id)
      %EditOperation{}

      iex> get_edit_operation!(bad_id)
      ** (Ecto.NoResultsError)

  """
  @spec get_edit_operation!(binary()) :: EditOperation.t()
  def get_edit_operation!(id), do: Repo.get!(EditOperation, id)

  @doc """
  Updates an edit operation.

  ## Examples

      iex> update_edit_operation(operation, %{params: %{gain: 0.5}})
      {:ok, %EditOperation{}}

      iex> update_edit_operation(operation, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_edit_operation(EditOperation.t(), map()) ::
          {:ok, EditOperation.t()} | {:error, Ecto.Changeset.t()}
  def update_edit_operation(%EditOperation{} = operation, attrs) do
    operation
    |> EditOperation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an edit operation.

  ## Examples

      iex> delete_edit_operation(operation)
      {:ok, %EditOperation{}}

      iex> delete_edit_operation(operation)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_edit_operation(EditOperation.t()) ::
          {:ok, EditOperation.t()} | {:error, Ecto.Changeset.t()}
  def delete_edit_operation(%EditOperation{} = operation) do
    Repo.delete(operation)
  end

  @doc """
  Reorders edit operations for a given stem by updating the position field
  of each operation to match its index in the provided list of IDs.

  The `ordered_ids` list defines the desired order: the first ID gets
  position 0, the second gets position 1, and so on.

  Runs inside a transaction so all updates succeed or none do.

  ## Examples

      iex> reorder_operations(stem_id, [id_3, id_1, id_2])
      {:ok, [%EditOperation{position: 0}, %EditOperation{position: 1}, %EditOperation{position: 2}]}

  """
  @spec reorder_operations(binary(), [binary()]) ::
          {:ok, [EditOperation.t()]} | {:error, term()}
  def reorder_operations(stem_id, ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index()
      |> Enum.map(fn {id, index} ->
        operation =
          EditOperation
          |> where([eo], eo.id == ^id and eo.stem_id == ^stem_id)
          |> Repo.one!()

        {:ok, updated} = update_edit_operation(operation, %{position: index})
        updated
      end)
    end)
  end

  @doc """
  Applies edit operations for a stem by preloading them in position order.

  Returns the ordered list of edit operations associated with the stem.
  This is the read-side of the non-destructive editing pipeline: callers
  iterate the returned operations to compute the final audio output.

  ## Examples

      iex> apply_operations(stem)
      [%EditOperation{position: 0}, %EditOperation{position: 1}]

  """
  @spec apply_operations(Stem.t()) :: [EditOperation.t()]
  def apply_operations(%Stem{} = stem) do
    EditOperation
    |> where([eo], eo.stem_id == ^stem.id)
    |> order_by([eo], asc: eo.position)
    |> Repo.all()
  end
end
