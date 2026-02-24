defmodule SoundForge.Audio.BatchProcessor do
  @moduledoc """
  Orchestrates batch stem separation for multiple tracks via lalal.ai.

  This is a service module (not an Oban worker) that coordinates batch
  processing by:

  1. Creating a `BatchJob` record to track overall progress
  2. Creating individual `ProcessingJob` records linked to the batch
  3. Enqueuing `LalalAIWorker` Oban jobs for each track
  4. Providing progress query and broadcast functions

  ## Usage

      {:ok, result} = BatchProcessor.start_batch(
        track_ids: ["uuid-1", "uuid-2", "uuid-3"],
        user_id: 1,
        stem_filter: "vocals",
        engine_opts: [splitter: "phoenix", preview: false]
      )

      # result contains:
      # %{batch_job: %BatchJob{}, processing_job_ids: ["job-uuid-1", ...], errors: []}

      # Later, recalculate progress from linked ProcessingJobs:
      {:ok, batch_job} = BatchProcessor.update_batch_progress(batch_job_id)

      # Query current status:
      {:ok, status} = BatchProcessor.get_batch_status(batch_job_id)

  ## PubSub

  Broadcasts on topic `"batch:{batch_job_id}"` with the following events:

    - `{:batch_progress, %{batch_job_id, status, completed_count, total_count}}`
    - `{:batch_complete, %{batch_job_id, completed_count, total_count, failed_count}}`

  ## Partial Failure Handling

  Individual track failures do not stop the batch. Each track is processed
  independently via its own Oban job. When `update_batch_progress/1` is
  called, it counts completed and failed jobs to determine overall status.
  """

  import Ecto.Query, warn: false

  alias SoundForge.Music
  alias SoundForge.Music.BatchJob
  alias SoundForge.Music.ProcessingJob
  alias SoundForge.Repo

  require Logger

  @max_batch_size 100

  @type start_opts :: [
          track_ids: [String.t()],
          user_id: integer(),
          stem_filter: String.t(),
          engine_opts: keyword()
        ]

  @type batch_result :: %{
          batch_job: BatchJob.t(),
          processing_job_ids: [String.t()],
          errors: [{String.t(), term()}]
        }

  @type batch_status :: %{
          batch_job_id: String.t(),
          status: :pending | :processing | :completed | :failed,
          total_count: integer(),
          completed_count: integer(),
          failed_count: integer(),
          in_progress_count: integer()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a batch stem separation job for the given track IDs.

  Creates a `BatchJob` record, then for each track creates a `ProcessingJob`
  linked to the batch and enqueues a `LalalAIWorker` Oban job. Tracks that
  do not have a completed download (no audio file on disk) are skipped and
  reported in the `errors` list.

  ## Options

    - `:track_ids` (required) - List of track UUIDs to process. Max #{@max_batch_size}.
    - `:user_id` (required) - The user initiating the batch.
    - `:stem_filter` - lalal.ai stem filter (default: `"vocals"`).
    - `:engine_opts` - Keyword list passed through to the worker:
      - `:splitter` - lalal.ai model (default: `"phoenix"`)
      - `:preview` - Boolean, preview mode (default: `false`)

  ## Returns

    - `{:ok, batch_result}` on success (even if some tracks were skipped)
    - `{:error, reason}` if the batch could not be created at all
  """
  @spec start_batch(start_opts()) :: {:ok, batch_result()} | {:error, term()}
  def start_batch(opts) do
    track_ids = Keyword.fetch!(opts, :track_ids)
    user_id = Keyword.fetch!(opts, :user_id)
    stem_filter = Keyword.get(opts, :stem_filter, "vocals")
    engine_opts = Keyword.get(opts, :engine_opts, [])

    with :ok <- validate_batch_size(track_ids),
         {:ok, batch_job} <- create_batch_job(user_id, length(track_ids), stem_filter, engine_opts) do
      {processing_job_ids, errors} =
        enqueue_tracks(batch_job.id, track_ids, stem_filter, engine_opts)

      # If we created at least one job, move batch to :processing
      if processing_job_ids != [] do
        update_batch_status(batch_job, :processing)
      end

      broadcast_batch_progress(batch_job.id)

      {:ok,
       %{
         batch_job: Repo.get!(BatchJob, batch_job.id),
         processing_job_ids: processing_job_ids,
         errors: errors
       }}
    end
  end

  @doc """
  Recalculates and persists the `completed_count` on a `BatchJob` by
  counting its linked `ProcessingJob` records that have reached a terminal
  state (`:completed` or `:failed`).

  If all jobs are terminal, the batch status is set to `:completed` (or
  `:failed` if every single job failed). Broadcasts progress on the batch
  PubSub topic.

  Returns the updated `BatchJob`.
  """
  @spec update_batch_progress(String.t()) :: {:ok, BatchJob.t()} | {:error, term()}
  def update_batch_progress(batch_job_id) do
    batch_job = Repo.get(BatchJob, batch_job_id)

    if is_nil(batch_job) do
      {:error, :not_found}
    else
      counts = count_job_states(batch_job_id)

      completed_count = counts.completed + counts.failed
      new_status = determine_batch_status(batch_job.total_count, counts)

      {:ok, updated} =
        batch_job
        |> BatchJob.changeset(%{
          completed_count: completed_count,
          status: new_status
        })
        |> Repo.update()

      broadcast_batch_progress(batch_job_id)

      if new_status in [:completed, :failed] do
        broadcast_batch_complete(batch_job_id, counts)
      end

      {:ok, updated}
    end
  end

  @doc """
  Returns a status summary for a batch job, including per-state counts
  derived from the linked `ProcessingJob` records.
  """
  @spec get_batch_status(String.t()) :: {:ok, batch_status()} | {:error, :not_found}
  def get_batch_status(batch_job_id) do
    batch_job = Repo.get(BatchJob, batch_job_id)

    if is_nil(batch_job) do
      {:error, :not_found}
    else
      counts = count_job_states(batch_job_id)

      {:ok,
       %{
         batch_job_id: batch_job.id,
         status: batch_job.status,
         total_count: batch_job.total_count,
         completed_count: counts.completed,
         failed_count: counts.failed,
         in_progress_count: counts.in_progress
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp validate_batch_size(track_ids) when length(track_ids) > @max_batch_size do
    {:error, {:batch_too_large, "Maximum batch size is #{@max_batch_size}, got #{length(track_ids)}"}}
  end

  defp validate_batch_size([]) do
    {:error, :empty_batch}
  end

  defp validate_batch_size(_track_ids), do: :ok

  defp create_batch_job(user_id, total_count, stem_filter, engine_opts) do
    splitter = Keyword.get(engine_opts, :splitter, "phoenix")
    preview = Keyword.get(engine_opts, :preview, false)

    %BatchJob{}
    |> BatchJob.changeset(%{
      user_id: user_id,
      total_count: total_count,
      status: :pending,
      completed_count: 0,
      options: %{
        "stem_filter" => stem_filter,
        "splitter" => splitter,
        "preview" => preview,
        "engine" => "lalalai"
      }
    })
    |> Repo.insert()
  end

  @spec enqueue_tracks(String.t(), [String.t()], String.t(), keyword()) ::
          {[String.t()], [{String.t(), term()}]}
  defp enqueue_tracks(batch_job_id, track_ids, stem_filter, engine_opts) do
    splitter = Keyword.get(engine_opts, :splitter, "phoenix")
    preview = Keyword.get(engine_opts, :preview, false)

    Enum.reduce(track_ids, {[], []}, fn track_id, {job_ids, errors} ->
      case enqueue_single_track(batch_job_id, track_id, stem_filter, splitter, preview) do
        {:ok, processing_job_id} ->
          {[processing_job_id | job_ids], errors}

        {:error, reason} ->
          Logger.warning(
            "BatchProcessor: skipping track #{track_id} in batch #{batch_job_id}: #{inspect(reason)}"
          )

          {job_ids, [{track_id, reason} | errors]}
      end
    end)
    |> then(fn {job_ids, errors} -> {Enum.reverse(job_ids), Enum.reverse(errors)} end)
  end

  defp enqueue_single_track(batch_job_id, track_id, stem_filter, splitter, preview) do
    with {:ok, file_path} <- Music.get_download_path(track_id),
         {:ok, processing_job} <- create_processing_job(batch_job_id, track_id, stem_filter, splitter, preview),
         {:ok, _oban_job} <- insert_oban_job(processing_job, track_id, file_path, stem_filter, splitter, preview) do
      {:ok, processing_job.id}
    end
  end

  defp create_processing_job(batch_job_id, track_id, _stem_filter, _splitter, preview) do
    Music.create_processing_job(%{
      track_id: track_id,
      batch_job_id: batch_job_id,
      status: :queued,
      engine: "lalalai",
      preview: preview,
      progress: 0
    })
  end

  defp insert_oban_job(processing_job, track_id, file_path, stem_filter, splitter, preview) do
    %{
      "track_id" => track_id,
      "job_id" => processing_job.id,
      "file_path" => file_path,
      "stem_filter" => stem_filter,
      "splitter" => splitter,
      "preview" => preview
    }
    |> SoundForge.Jobs.LalalAIWorker.new()
    |> Oban.insert()
  end

  defp count_job_states(batch_job_id) do
    query =
      from pj in ProcessingJob,
        where: pj.batch_job_id == ^batch_job_id,
        group_by: pj.status,
        select: {pj.status, count(pj.id)}

    status_counts =
      query
      |> Repo.all()
      |> Map.new()

    %{
      completed: Map.get(status_counts, :completed, 0),
      failed: Map.get(status_counts, :failed, 0),
      in_progress:
        Map.get(status_counts, :queued, 0) +
          Map.get(status_counts, :downloading, 0) +
          Map.get(status_counts, :processing, 0)
    }
  end

  defp determine_batch_status(total_count, counts) do
    terminal_count = counts.completed + counts.failed

    cond do
      terminal_count >= total_count and counts.completed == 0 ->
        :failed

      terminal_count >= total_count ->
        :completed

      terminal_count > 0 ->
        :processing

      true ->
        :pending
    end
  end

  defp update_batch_status(batch_job, new_status) do
    batch_job
    |> BatchJob.changeset(%{status: new_status})
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # PubSub broadcasts
  # ---------------------------------------------------------------------------

  defp broadcast_batch_progress(batch_job_id) do
    batch_job = Repo.get!(BatchJob, batch_job_id)
    counts = count_job_states(batch_job_id)

    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "batch:#{batch_job_id}",
      {:batch_progress,
       %{
         batch_job_id: batch_job_id,
         status: batch_job.status,
         completed_count: counts.completed + counts.failed,
         total_count: batch_job.total_count
       }}
    )
  end

  defp broadcast_batch_complete(batch_job_id, counts) do
    batch_job = Repo.get!(BatchJob, batch_job_id)

    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "batch:#{batch_job_id}",
      {:batch_complete,
       %{
         batch_job_id: batch_job_id,
         completed_count: counts.completed,
         total_count: batch_job.total_count,
         failed_count: counts.failed
       }}
    )
  end
end
