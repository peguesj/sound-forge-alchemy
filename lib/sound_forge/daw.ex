defmodule SoundForge.DAW do
  @moduledoc """
  The DAW context.

  Provides two areas of functionality:

  1. **Project CRUD** — management of `DawProject` records and their
     track lanes (`DawProjectTrack`), including CrateDigger import.

  2. **Non-destructive edit operations** — `EditOperation` records applied
     to audio stems.  Operations are ordered by position and replayed to
     produce the final edited audio output.
  """

  import Ecto.Query, warn: false
  alias SoundForge.Repo

  alias SoundForge.CrateDigger.Crate
  alias SoundForge.Daw.{DawProject, DawProjectTrack}
  alias SoundForge.DAW.EditOperation
  alias SoundForge.Music.{Stem, Track}

  # ---------------------------------------------------------------------------
  # Project CRUD
  # ---------------------------------------------------------------------------

  @doc """
  List all DAW projects for a user, ordered by most recently updated.

  Preloads `:project_tracks` on each project.
  """
  @spec list_projects(integer()) :: [DawProject.t()]
  def list_projects(user_id) do
    DawProject
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
    |> Repo.preload(:project_tracks)
  end

  @doc """
  Fetch a single DAW project by ID, raising `Ecto.NoResultsError` if missing.

  Preloads `project_tracks` with their associated `audio_file` (`Music.Track`).
  """
  @spec get_project!(binary()) :: DawProject.t()
  def get_project!(id) do
    DawProject
    |> Repo.get!(id)
    |> Repo.preload(project_tracks: :audio_file)
  end

  @doc "Create a new DAW project for `user_id` with the given `attrs`."
  @spec create_project(integer(), map()) ::
          {:ok, DawProject.t()} | {:error, Ecto.Changeset.t()}
  def create_project(user_id, attrs \\ %{}) do
    %DawProject{}
    |> DawProject.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @doc "Update an existing DAW project."
  @spec update_project(DawProject.t(), map()) ::
          {:ok, DawProject.t()} | {:error, Ecto.Changeset.t()}
  def update_project(%DawProject{} = project, attrs) do
    project
    |> DawProject.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a DAW project (cascades to project_tracks via DB constraint)."
  @spec delete_project(DawProject.t()) ::
          {:ok, DawProject.t()} | {:error, Ecto.Changeset.t()}
  def delete_project(%DawProject{} = project) do
    Repo.delete(project)
  end

  # ---------------------------------------------------------------------------
  # Track-lane management
  # ---------------------------------------------------------------------------

  @doc """
  Add a track lane to a project.

  `attrs` should include `:position` and optionally `:audio_file_id`,
  `:title`, `:track_type`, and `:metadata`.
  """
  @spec add_track(binary(), map()) ::
          {:ok, DawProjectTrack.t()} | {:error, Ecto.Changeset.t()}
  def add_track(project_id, attrs) do
    result =
      %DawProjectTrack{}
      |> DawProjectTrack.changeset(Map.put(attrs, :daw_project_id, project_id))
      |> Repo.insert()

    case result do
      {:ok, _track} ->
        %{"project_id" => project_id}
        |> SoundForge.Jobs.DawClassifyWorker.new()
        |> Oban.insert()

        result

      {:error, _changeset} ->
        result
    end
  end

  @doc """
  Remove a track lane from a project.

  Accepts either a `DawProjectTrack` struct or a binary ID string.
  """
  @spec remove_track(DawProjectTrack.t() | binary()) ::
          {:ok, DawProjectTrack.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def remove_track(%DawProjectTrack{} = track) do
    Repo.delete(track)
  end

  def remove_track(id) when is_binary(id) do
    case Repo.get(DawProjectTrack, id) do
      nil -> {:error, :not_found}
      track -> Repo.delete(track)
    end
  end

  @doc """
  Reorder track lanes within a project.

  Accepts `project_id` and an ordered list of `DawProjectTrack` IDs.
  Each track's `position` is updated to its zero-based index in the list.
  """
  @spec reorder_tracks(binary(), [binary()]) :: :ok | {:error, term()}
  def reorder_tracks(project_id, track_ids) when is_list(track_ids) do
    Repo.transaction(fn ->
      track_ids
      |> Enum.with_index()
      |> Enum.each(fn {track_id, index} ->
        DawProjectTrack
        |> where([t], t.id == ^track_id and t.daw_project_id == ^project_id)
        |> Repo.update_all(set: [position: index])
      end)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Update the semantic type of a track lane.

  Stores `:type` and `:manual` flag into the `metadata` map and also updates
  the `track_type` field directly.

  `opts` must include `:type` (atom or string). Optional `:manual` boolean
  (defaults to `false`).
  """
  @spec update_track_type(DawProjectTrack.t(), map()) ::
          {:ok, DawProjectTrack.t()} | {:error, Ecto.Changeset.t()}
  def update_track_type(%DawProjectTrack{} = track, %{type: type} = opts) do
    type_str = to_string(type)
    manual = Map.get(opts, :manual, false)

    updated_metadata =
      (track.metadata || %{})
      |> Map.put("type", type_str)
      |> Map.put("manual", manual)

    track
    |> DawProjectTrack.changeset(%{track_type: type_str, metadata: updated_metadata})
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # CrateDigger import
  # ---------------------------------------------------------------------------

  @doc """
  Import tracks from a CrateDigger crate into a DAW project.

  For each `spotify_track_id` in the crate's `track_configs`, a matching
  downloaded `Music.Track` is looked up by `spotify_id`. Tracks whose
  `audio_file_id` already appears in the project are skipped.

  Returns `{:ok, %{imported: count, skipped: count}}`.
  """
  @spec import_from_crate(binary(), binary()) ::
          {:ok, %{imported: non_neg_integer(), skipped: non_neg_integer()}}
          | {:error, :crate_not_found | :project_not_found}
  def import_from_crate(project_id, crate_id) do
    project = Repo.get(DawProject, project_id)
    crate = Repo.get(Crate, crate_id)

    cond do
      is_nil(project) -> {:error, :project_not_found}
      is_nil(crate) -> {:error, :crate_not_found}
      true -> do_import_from_crate(project, crate)
    end
  end

  defp do_import_from_crate(project, crate) do
    crate = Repo.preload(crate, :track_configs)

    spotify_ids =
      crate.track_configs
      |> Enum.map(& &1.spotify_track_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    matched_tracks =
      Track
      |> where([t], t.spotify_id in ^spotify_ids)
      |> Repo.all()

    existing_audio_file_ids =
      DawProjectTrack
      |> where([pt], pt.daw_project_id == ^project.id)
      |> select([pt], pt.audio_file_id)
      |> Repo.all()
      |> MapSet.new()

    current_count =
      DawProjectTrack
      |> where([pt], pt.daw_project_id == ^project.id)
      |> Repo.aggregate(:count, :id)

    new_tracks = Enum.reject(matched_tracks, &MapSet.member?(existing_audio_file_ids, &1.id))
    already_present = length(matched_tracks) - length(new_tracks)

    {imported, failed} =
      new_tracks
      |> Enum.with_index(current_count)
      |> Enum.reduce({0, 0}, fn {track, position}, {imp, fail} ->
        attrs = %{
          daw_project_id: project.id,
          audio_file_id: track.id,
          title: track.title,
          position: position,
          track_type: "audio"
        }

        case %DawProjectTrack{} |> DawProjectTrack.changeset(attrs) |> Repo.insert() do
          {:ok, _} -> {imp + 1, fail}
          {:error, _} -> {imp, fail + 1}
        end
      end)

    {:ok, %{imported: imported, skipped: already_present + failed}}
  end

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
