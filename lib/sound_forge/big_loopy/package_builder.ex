defmodule SoundForge.BigLoopy.PackageBuilder do
  @moduledoc """
  PackageBuilder — assembles extracted loop files into a downloadable ZIP archive.

  Uses Erlang's `:zip` stdlib module; no external dependencies required.
  """

  require Logger

  @doc """
  Builds a ZIP archive containing all loop files for an AlchemySet.

  `alchemy_set_id` is used to name the archive and organize the output path.
  `loop_files` is a list of absolute file paths to include in the archive.

  Returns `{:ok, zip_path}` on success or `{:error, reason}` on failure.
  The ZIP is written to `priv/static/uploads/packages/<alchemy_set_id>.zip`.
  """
  @spec build(binary(), [String.t()]) :: {:ok, String.t()} | {:error, term()}
  def build(alchemy_set_id, loop_files) when is_list(loop_files) do
    output_dir = Path.join([:code.priv_dir(:sound_forge), "static", "uploads", "packages"])
    File.mkdir_p!(output_dir)

    zip_path = Path.join(output_dir, "#{alchemy_set_id}.zip")

    # Build list of {filename_in_zip, file_path} tuples
    entries =
      loop_files
      |> Enum.filter(&File.exists?/1)
      |> Enum.map(fn path ->
        {Path.basename(path) |> String.to_charlist(), path |> String.to_charlist()}
      end)

    if entries == [] do
      Logger.warning("[PackageBuilder] No valid loop files to package for #{alchemy_set_id}")
      {:error, :no_files}
    else
      zip_path_charlist = zip_path |> String.to_charlist()

      case :zip.create(zip_path_charlist, entries) do
        {:ok, _path} ->
          Logger.info("[PackageBuilder] Created #{zip_path} with #{length(entries)} files")
          {:ok, zip_path}

        {:error, reason} ->
          Logger.error("[PackageBuilder] Failed to create ZIP for #{alchemy_set_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
