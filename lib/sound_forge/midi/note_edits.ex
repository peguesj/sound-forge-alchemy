defmodule SoundForge.MIDI.NoteEdits do
  @moduledoc """
  Context for managing user-created MIDI note edits on a track's piano roll.
  """

  import Ecto.Query, warn: false

  alias SoundForge.Repo
  alias SoundForge.MIDI.NoteEdit

  @doc """
  Lists all user note edits for a track, ordered by onset ascending.
  """
  @spec list_note_edits(binary(), term()) :: [NoteEdit.t()]
  def list_note_edits(track_id, user_id) do
    NoteEdit
    |> where([n], n.track_id == ^track_id and n.user_id == ^user_id)
    |> order_by([n], asc: n.onset_sec)
    |> Repo.all()
  end

  @doc """
  Creates a note edit.
  """
  @spec create_note_edit(map()) :: {:ok, NoteEdit.t()} | {:error, Ecto.Changeset.t()}
  def create_note_edit(attrs \\ %{}) do
    %NoteEdit{}
    |> NoteEdit.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a single note edit by ID.
  """
  @spec get_note_edit(binary()) :: NoteEdit.t() | nil
  def get_note_edit(id), do: Repo.get(NoteEdit, id)

  @doc """
  Deletes a note edit.
  """
  @spec delete_note_edit(NoteEdit.t()) :: {:ok, NoteEdit.t()} | {:error, Ecto.Changeset.t()}
  def delete_note_edit(%NoteEdit{} = note_edit) do
    Repo.delete(note_edit)
  end

  @doc """
  Deletes all note edits for a track belonging to a user.
  """
  @spec delete_all_note_edits(binary(), term()) :: {non_neg_integer(), nil}
  def delete_all_note_edits(track_id, user_id) do
    NoteEdit
    |> where([n], n.track_id == ^track_id and n.user_id == ^user_id)
    |> Repo.delete_all()
  end
end
