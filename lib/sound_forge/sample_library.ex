defmodule SoundForge.SampleLibrary do
  @moduledoc """
  The Sample Library context.

  Manages SamplePacks and SampleFiles — the organizational layer for
  browsing, searching, and importing sample collections into SFA.

  Sample packs can be imported from:
  - Local filesystem paths (via ManifestImportWorker)
  - Splice local library (via SpliceImportWorker integration)
  - Manual upload

  Each pack contains SampleFiles with rich metadata (BPM, key, category, tags).
  """

  import Ecto.Query, warn: false
  require Logger

  alias SoundForge.Repo
  alias SoundForge.SampleLibrary.{SampleFile, SamplePack}

  # ---------------------------------------------------------------------------
  # SamplePack CRUD
  # ---------------------------------------------------------------------------

  @doc "Lists all SamplePacks for a user, ordered by most recently created."
  @spec list_packs(integer()) :: [SamplePack.t()]
  def list_packs(user_id) do
    SamplePack
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc "Lists ALL SamplePacks across all users (platform_admin only)."
  @spec list_all_packs() :: [SamplePack.t()]
  def list_all_packs do
    SamplePack
    |> order_by([p], desc: p.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Gets a single SamplePack by id. Returns nil if not found."
  @spec get_pack(binary()) :: SamplePack.t() | nil
  def get_pack(id), do: Repo.get(SamplePack, id)

  @doc "Creates a SamplePack."
  @spec create_pack(map()) :: {:ok, SamplePack.t()} | {:error, Ecto.Changeset.t()}
  def create_pack(attrs \\ %{}) do
    %SamplePack{}
    |> SamplePack.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a SamplePack."
  @spec update_pack(SamplePack.t(), map()) :: {:ok, SamplePack.t()} | {:error, Ecto.Changeset.t()}
  def update_pack(%SamplePack{} = pack, attrs) do
    pack
    |> SamplePack.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a SamplePack and all associated SampleFiles."
  @spec delete_pack(SamplePack.t()) :: {:ok, SamplePack.t()} | {:error, Ecto.Changeset.t()}
  def delete_pack(%SamplePack{} = pack), do: Repo.delete(pack)

  # ---------------------------------------------------------------------------
  # SampleFile queries
  # ---------------------------------------------------------------------------

  @doc "Lists all SampleFiles in a given pack."
  @spec list_files(binary()) :: [SampleFile.t()]
  def list_files(pack_id) do
    SampleFile
    |> where([f], f.pack_id == ^pack_id)
    |> order_by([f], asc: f.name)
    |> Repo.all()
  end

  @doc """
  Searches and filters SampleFiles.

  Filter map accepts these optional keys:
  - `:query`    — text search on file name (case-insensitive)
  - `:bpm_min`  — minimum BPM (inclusive)
  - `:bpm_max`  — maximum BPM (inclusive)
  - `:key`      — exact key match (e.g. "C", "Am")
  - `:category` — exact category match
  - `:pack_id`  — limit to a specific pack
  - `:limit`    — max results (default 50)

  Returns a list of SampleFiles ordered by name.
  """
  @spec search_files(integer(), map()) :: [SampleFile.t()]
  def search_files(user_id, filters \\ %{}) do
    limit = Map.get(filters, :limit, 50)

    # Build base query restricted to user's packs
    base =
      from f in SampleFile,
        join: p in SamplePack,
        on: f.pack_id == p.id,
        where: p.user_id == ^user_id,
        order_by: [asc: f.name],
        limit: ^limit

    Enum.reduce(filters, base, fn
      {:query, q}, query when is_binary(q) and q != "" ->
        like = "%#{q}%"
        where(query, [f], ilike(f.name, ^like))

      {:bpm_min, min}, query when is_number(min) ->
        where(query, [f], not is_nil(f.bpm) and f.bpm >= ^min)

      {:bpm_max, max}, query when is_number(max) ->
        where(query, [f], not is_nil(f.bpm) and f.bpm <= ^max)

      {:key, key}, query when is_binary(key) and key != "" ->
        where(query, [f], f.key == ^key)

      {:category, cat}, query when is_binary(cat) and cat != "" ->
        where(query, [f], f.category == ^cat)

      {:pack_id, pack_id}, query when is_binary(pack_id) ->
        where(query, [f], f.pack_id == ^pack_id)

      _other, query ->
        query
    end)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Manifest import
  # ---------------------------------------------------------------------------

  @doc """
  Imports SampleFiles into `pack` from a JSON manifest file.

  The manifest is a JSON array of objects:
      [
        {
          "name": "kick_01.wav",
          "file_path": "/path/to/kick_01.wav",
          "bpm": 120.0,
          "key": "C",
          "category": "drums",
          "sample_type": "one_shot",
          "duration_ms": 250,
          "file_size": 44100
        },
        ...
      ]

  Uses Repo.insert_all/2 for efficient bulk insert.
  Returns `{:ok, count}` on success or `{:error, reason}` on failure.
  """
  @spec import_from_manifest(SamplePack.t(), String.t()) :: {:ok, integer()} | {:error, term()}
  def import_from_manifest(%SamplePack{} = pack, manifest_path) do
    with {:ok, raw} <- File.read(manifest_path),
         {:ok, entries} <- Jason.decode(raw),
         true <- is_list(entries) do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      rows =
        Enum.map(entries, fn entry ->
          id = Ecto.UUID.generate()

          %{
            id: id,
            pack_id: pack.id,
            name: Map.get(entry, "name", Path.basename(Map.get(entry, "file_path", "unknown"))),
            file_path: Map.get(entry, "file_path", ""),
            bpm: to_float_opt(Map.get(entry, "bpm")),
            key: Map.get(entry, "key"),
            category: Map.get(entry, "category"),
            sample_type: Map.get(entry, "sample_type"),
            duration_ms: Map.get(entry, "duration_ms"),
            file_size: Map.get(entry, "file_size"),
            tags: Map.get(entry, "tags", []),
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} = Repo.insert_all(SampleFile, rows, on_conflict: :nothing)

      # Update pack total_files count
      update_pack(pack, %{total_files: count, status: "ready"})

      Logger.info("[SampleLibrary] Imported #{count} files into pack #{pack.name}")
      {:ok, count}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :manifest_not_a_list}
    end
  end

  defp to_float_opt(nil), do: nil
  defp to_float_opt(v) when is_float(v), do: v
  defp to_float_opt(v) when is_integer(v), do: v * 1.0
  defp to_float_opt(_), do: nil
end
