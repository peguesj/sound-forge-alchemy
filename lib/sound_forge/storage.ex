defmodule SoundForge.Storage do
  @moduledoc """
  File storage context for audio files, stems, and uploads.
  Uses local filesystem storage with configurable base path.
  """

  @default_base_path "priv/uploads"

  def base_path do
    Application.get_env(:sound_forge, :storage_path, @default_base_path)
  end

  def downloads_path, do: Path.join(base_path(), "downloads")
  def stems_path, do: Path.join(base_path(), "stems")
  def analysis_path, do: Path.join(base_path(), "analysis")

  @doc "Ensure all storage directories exist"
  def ensure_directories! do
    Enum.each([downloads_path(), stems_path(), analysis_path()], &File.mkdir_p!/1)
  end

  @doc "Store a file in the given subdirectory"
  def store_file(source_path, subdirectory, filename) do
    dest_dir = Path.join(base_path(), subdirectory)
    File.mkdir_p!(dest_dir)
    dest_path = Path.join(dest_dir, filename)

    case File.cp(source_path, dest_path) do
      :ok -> {:ok, dest_path}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Get full path for a stored file"
  def file_path(subdirectory, filename) do
    Path.join([base_path(), subdirectory, filename])
  end

  @doc "Check if a file exists in storage"
  def file_exists?(subdirectory, filename) do
    subdirectory
    |> file_path(filename)
    |> File.exists?()
  end

  @doc "Delete a file from storage"
  def delete_file(subdirectory, filename) do
    path = file_path(subdirectory, filename)
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok  # Already gone
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Get storage statistics"
  def stats do
    base = base_path()
    if File.dir?(base) do
      {file_count, total_size} = count_files(base)
      %{
        base_path: base,
        file_count: file_count,
        total_size_bytes: total_size,
        total_size_mb: Float.round(total_size / (1024 * 1024), 2)
      }
    else
      %{base_path: base, file_count: 0, total_size_bytes: 0, total_size_mb: 0.0}
    end
  end

  @doc "Clean up orphaned files not referenced in the database"
  def cleanup_orphaned do
    known_paths = referenced_file_paths()
    base = base_path()

    if File.dir?(base) do
      orphans = find_orphaned_files(base, known_paths)

      deleted_count =
        Enum.count(orphans, fn path ->
          case File.rm(path) do
            :ok -> true
            {:error, :enoent} -> true
            _ -> false
          end
        end)

      {:ok, deleted_count}
    else
      {:ok, 0}
    end
  end

  defp referenced_file_paths do
    import Ecto.Query

    stem_paths =
      SoundForge.Music.Stem
      |> select([s], s.file_path)
      |> where([s], not is_nil(s.file_path))
      |> SoundForge.Repo.all()

    download_paths =
      SoundForge.Music.DownloadJob
      |> select([d], d.output_path)
      |> where([d], not is_nil(d.output_path))
      |> SoundForge.Repo.all()

    base = base_path()

    (stem_paths ++ download_paths)
    |> Enum.map(fn path ->
      if String.starts_with?(path, "/"), do: path, else: Path.join(base, path)
    end)
    |> MapSet.new()
  end

  defp find_orphaned_files(dir, known_paths) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          path = Path.join(dir, entry)

          if File.dir?(path) do
            find_orphaned_files(path, known_paths)
          else
            if MapSet.member?(known_paths, path), do: [], else: [path]
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp count_files(dir) do
    dir
    |> File.ls!()
    |> Enum.reduce({0, 0}, fn entry, {count, size} ->
      path = Path.join(dir, entry)
      if File.dir?(path) do
        {sub_count, sub_size} = count_files(path)
        {count + sub_count, size + sub_size}
      else
        case File.stat(path) do
          {:ok, %{size: file_size}} -> {count + 1, size + file_size}
          _ -> {count, size}
        end
      end
    end)
  end
end
