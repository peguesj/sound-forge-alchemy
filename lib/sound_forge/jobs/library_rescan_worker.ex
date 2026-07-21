defmodule SoundForge.Jobs.LibraryRescanWorker do
  @moduledoc """
  Oban worker that performs a full library integrity scan:
  - Validates downloaded audio files still exist on disk
  - Validates stem files still exist on disk
  - Broadcasts scan results via PubSub for real-time UI updates

  Can be enqueued on-demand from Settings or run on a schedule.
  """
  use Oban.Worker, queue: :analysis, max_attempts: 1

  require Logger
  import Ecto.Query
  alias SoundForge.{Music, Repo, Storage}
  alias SoundForge.Music.{DownloadJob, Stem}

  @pubsub SoundForge.PubSub
  @pubsub_topic "library:scan"

  def pubsub_topic, do: @pubsub_topic

  @impl true
  def perform(%Oban.Job{args: args}) do
    user_id = Map.get(args, "user_id")

    Logger.info(
      "[LibraryRescanWorker] Starting library integrity scan (user: #{inspect(user_id)})"
    )

    audio_results = scan_audio_files()
    stem_results = scan_stem_files()
    stats = Storage.stats()

    results = %{
      audio: audio_results,
      stems: stem_results,
      stats: stats,
      scanned_at: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(
      @pubsub,
      @pubsub_topic,
      {:library_scan_complete, user_id, results}
    )

    Logger.info(
      "[LibraryRescanWorker] Scan complete: " <>
        "audio #{audio_results.valid}/#{audio_results.total} valid, " <>
        "stems #{stem_results.valid}/#{stem_results.total} valid"
    )

    {:ok, results}
  end

  defp scan_audio_files do
    completed_jobs =
      DownloadJob
      |> where([dj], dj.status == :completed)
      |> where([dj], not is_nil(dj.output_path))
      |> Repo.all()

    results =
      Enum.map(completed_jobs, fn job ->
        case Storage.validate_audio_file(job.output_path) do
          :ok ->
            :valid

          {:error, _reason} ->
            Music.update_download_job(job, %{
              status: :failed,
              error: "File missing (detected by library scan)"
            })

            :missing
        end
      end)

    %{
      total: length(results),
      valid: Enum.count(results, &(&1 == :valid)),
      missing: Enum.count(results, &(&1 == :missing))
    }
  end

  defp scan_stem_files do
    stems =
      Stem
      |> where([s], not is_nil(s.file_path))
      |> Repo.all()

    results =
      Enum.map(stems, fn stem ->
        resolved = Storage.resolve_path(stem.file_path)

        if File.exists?(resolved), do: :valid, else: :missing
      end)

    %{
      total: length(results),
      valid: Enum.count(results, &(&1 == :valid)),
      missing: Enum.count(results, &(&1 == :missing))
    }
  end
end
