defmodule Mix.Tasks.SampleLibrary.Acquire do
  @shortdoc "Import a sample directory into the SFA sample library"
  @moduledoc """
  Mix task that validates a sample source directory and prints instructions
  for running the sample acquisition script.

  ## Usage

      mix sample_library.acquire --path /path/to/samples

  ## Options

    * `--path` - Path to the directory containing sample files (required)
    * `--user-id` - User ID to associate samples with (optional, defaults to first admin)
    * `--dry-run` - Validate without importing

  ## Example

      mix sample_library.acquire --path ~/samples/splice/drums

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [path: :string, user_id: :integer, dry_run: :boolean],
        aliases: [p: :path, u: :user_id, d: :dry_run]
      )

    path = Keyword.get(opts, :path)
    dry_run = Keyword.get(opts, :dry_run, false)

    if is_nil(path) do
      Mix.raise("--path is required. Usage: mix sample_library.acquire --path /path/to/samples")
    end

    unless File.dir?(path) do
      Mix.raise("Path does not exist or is not a directory: #{path}")
    end

    audio_extensions = ~w(.wav .mp3 .aif .aiff .flac .ogg)

    count =
      path
      |> File.ls!()
      |> Enum.filter(fn f ->
        ext = f |> Path.extname() |> String.downcase()
        ext in audio_extensions
      end)
      |> length()

    Mix.shell().info("Source path: #{path}")
    Mix.shell().info("Audio files found: #{count}")

    if dry_run do
      Mix.shell().info("[dry-run] Would import #{count} files from #{path}")
    else
      Mix.shell().info("To import these files, use the SampleLibrary context:")
      Mix.shell().info("  SoundForge.SampleLibrary.create_pack(%{name: \"My Pack\", user_id: USER_ID})")
      Mix.shell().info("  SoundForge.Jobs.ManifestImportWorker.new(%{\"pack_id\" => PACK_ID, \"manifest_path\" => MANIFEST_PATH})")
      Mix.shell().info("  |> Oban.insert()")
      Mix.shell().info("")
      Mix.shell().info("Or use the acquire.sh script in priv/sample_acquisition/")
    end
  end
end
