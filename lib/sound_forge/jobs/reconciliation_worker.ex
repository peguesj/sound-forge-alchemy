defmodule SoundForge.Jobs.ReconciliationWorker do
  @moduledoc """
  Oban worker that audits completed download_jobs and verifies that the
  referenced audio files still exist on disk.

  If a file is missing, marks the download_job as :failed with an error message.
  This reconciles database state with filesystem reality.

  Scheduled to run daily via Oban.Cron (configured in application.ex).
  """
  use Oban.Worker, queue: :analysis, max_attempts: 1

  require Logger
  import Ecto.Query
  alias SoundForge.{Music, Repo, Storage}

  @impl true
  def perform(%Oban.Job{}) do
    Logger.info("[ReconciliationWorker] Starting download_jobs audit")

    completed_jobs =
      Music.DownloadJob
      |> where([dj], dj.status == :completed)
      |> where([dj], not is_nil(dj.output_path))
      |> Repo.all()

    results =
      Enum.map(completed_jobs, fn job ->
        validate_and_update_job(job)
      end)

    failed_count = Enum.count(results, &(&1 == :invalidated))
    valid_count = Enum.count(results, &(&1 == :valid))

    Logger.info(
      "[ReconciliationWorker] Audit complete: #{valid_count} valid, #{failed_count} invalidated"
    )

    {:ok, %{valid: valid_count, invalidated: failed_count}}
  end

  defp validate_and_update_job(job) do
    case Storage.validate_audio_file(job.output_path) do
      :ok ->
        :valid

      {:error, reason} ->
        error_msg = "File validation failed: #{reason}"
        Logger.warning("[ReconciliationWorker] Job #{job.id} invalidated: #{error_msg}")

        # Mark the job as failed so downstream workers don't attempt to process it
        Music.update_download_job(job, %{
          status: :failed,
          error: "#{error_msg} (detected by reconciliation)"
        })

        :invalidated
    end
  end
end
