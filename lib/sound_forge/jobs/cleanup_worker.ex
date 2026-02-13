defmodule SoundForge.Jobs.CleanupWorker do
  @moduledoc """
  Oban worker for periodic cleanup of orphaned storage files.
  Runs on a cron schedule to remove files not referenced in the database.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    {:ok, count} = SoundForge.Storage.cleanup_orphaned()

    if count > 0 do
      Logger.info("Storage cleanup removed #{count} orphaned files")
    end

    :ok
  rescue
    error ->
      Logger.error("Storage cleanup failed: #{inspect(error)}")
      {:error, inspect(error)}
  end
end
