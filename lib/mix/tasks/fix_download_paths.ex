defmodule Mix.Tasks.FixDownloadPaths do
  @moduledoc """
  Fixes double-nested download paths in the database.

  The download worker previously used relative paths for output_dir, causing
  files to be saved at priv/uploads/downloads/priv/uploads/downloads/.
  This task corrects the paths to use absolute paths and moves files.

  ## Usage

      mix fix_download_paths          # Dry run
      mix fix_download_paths --apply  # Apply changes
  """
  use Mix.Task

  @shortdoc "Fix double-nested download job output paths"

  @impl Mix.Task
  def run(args) do
    apply? = "--apply" in args
    Mix.Task.run("app.start")

    import Ecto.Query
    alias SoundForge.Repo
    alias SoundForge.Music.DownloadJob

    app_root = File.cwd!()
    correct_dir = Path.join([app_root, "priv", "uploads", "downloads"])

    # Find jobs with double-nested paths
    jobs =
      DownloadJob
      |> where([d], like(d.output_path, "%priv/uploads/downloads/priv/uploads/downloads/%"))
      |> Repo.all()

    if jobs == [] do
      Mix.shell().info("No double-nested paths found. Nothing to fix.")
    else
      unless apply?, do: Mix.shell().info("=== DRY RUN (pass --apply to make changes) ===")
      Mix.shell().info("Found #{length(jobs)} affected download job(s).\n")

      results =
        Enum.map(jobs, fn job ->
          filename = Path.basename(job.output_path)
          new_path = Path.join(correct_dir, filename)

          Mix.shell().info("Job #{job.id} (#{(job.track && job.track.title) || "unknown"})")
          Mix.shell().info("  Old: #{job.output_path}")
          Mix.shell().info("  New: #{new_path}")

          if apply? do
            # Move file if it exists at the old location
            old_abs =
              if String.starts_with?(job.output_path, "/"),
                do: job.output_path,
                else: Path.join(app_root, job.output_path)

            if File.exists?(old_abs) and old_abs != new_path do
              File.mkdir_p!(correct_dir)
              File.rename(old_abs, new_path)
            end

            # Update DB record
            job
            |> Ecto.Changeset.change(%{output_path: new_path})
            |> Repo.update!()

            Mix.shell().info("  Status: FIXED")
            :fixed
          else
            Mix.shell().info("  Status: WOULD FIX")
            :would_fix
          end
        end)

      fixed = Enum.count(results, &(&1 == :fixed))
      would_fix = Enum.count(results, &(&1 == :would_fix))

      Mix.shell().info("\n=== Summary ===")

      if apply? do
        Mix.shell().info("  Fixed: #{fixed}")
        cleanup_nested_dir(app_root)
      else
        Mix.shell().info("  Would fix: #{would_fix}")
        Mix.shell().info("\nRun with --apply to make these changes.")
      end
    end
  end

  defp cleanup_nested_dir(app_root) do
    nested = Path.join([app_root, "priv", "uploads", "downloads", "priv"])

    if File.exists?(nested) do
      case File.rm_rf(nested) do
        {:ok, removed} ->
          Mix.shell().info("  Cleaned up nested directory (#{length(removed)} items removed)")

        {:error, reason, path} ->
          Mix.shell().error("  Could not remove #{path}: #{inspect(reason)}")
      end
    end
  end
end
