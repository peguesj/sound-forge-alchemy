defmodule SoundForge.Jobs.BigLoopyTrackWorker do
  @moduledoc """
  Oban worker that processes a single track through the BigLoopy alchemy pipeline.

  For each track: fetches analysis, calls OmegaChop to assign stems, then
  calls LoopExtractor for each loop point in the recipe. Broadcasts progress
  via BigLoopyBroadcaster.

  Args:
    - "alchemy_set_id" — UUID of the parent AlchemySet
    - "track_id"       — UUID of the track to process
    - "recipe"         — map with loop points, stem preferences, etc.
  """
  use Oban.Worker,
    queue: :big_loopy,
    max_attempts: 3,
    priority: 3

  alias SoundForge.BigLoopy.{Broadcaster, OmegaChop}
  alias SoundForge.BigLoopy.LoopExtractor
  alias SoundForge.Music
  alias SoundForge.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "alchemy_set_id" => alchemy_set_id,
          "track_id" => track_id,
          "recipe" => recipe
        }
      }) do
    Logger.metadata(worker: "BigLoopyTrackWorker", track_id: track_id, alchemy_set_id: alchemy_set_id)
    Logger.info("[BigLoopyTrackWorker] Processing track #{track_id} for set #{alchemy_set_id}")

    Broadcaster.broadcast_track_progress(alchemy_set_id, %{
      track_id: track_id,
      status: "started",
      pct: 0
    })

    try do
      # Fetch analysis data for stem routing
      analysis =
        case Music.get_analysis_result_for_track(track_id) do
          nil -> %{}
          result -> Map.from_struct(result)
        end

      # Determine stem assignments
      stem_assignments = OmegaChop.assign_stems(analysis, recipe || %{})

      # Extract loops for each loop point in the recipe
      loop_points = Map.get(recipe || %{}, "loop_points", [])

      Broadcaster.broadcast_track_progress(alchemy_set_id, %{
        track_id: track_id,
        status: "extracting",
        pct: 25
      })

      # Fetch the track's local file path from its most recent completed download job
      track = track_id |> Music.get_track() |> then(fn t ->
        if t, do: Repo.preload(t, :download_jobs), else: nil
      end)

      local_path =
        (track && Map.get(track, :download_jobs, []) || [])
        |> Enum.filter(&(&1.status == :completed && &1.output_path))
        |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
        |> case do
          [job | _] -> job.output_path
          [] -> nil
        end

      loop_paths =
        if local_path do
          extract_loops(local_path, loop_points, stem_assignments, alchemy_set_id)
        else
          Logger.warning("[BigLoopyTrackWorker] No completed download for track #{track_id} — skipping extraction")
          []
        end

      Broadcaster.broadcast_track_complete(alchemy_set_id, %{
        track_id: track_id,
        loop_paths: loop_paths
      })

      :ok
    rescue
      e ->
        Logger.error("[BigLoopyTrackWorker] Error processing track #{track_id}: #{Exception.message(e)}")
        Broadcaster.broadcast_error(alchemy_set_id, Exception.message(e))
        {:error, Exception.message(e)}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp extract_loops(_file_path, [], _stem_assignments, _alchemy_set_id), do: []

  defp extract_loops(file_path, loop_points, _stem_assignments, alchemy_set_id) do
    loop_points
    |> Enum.with_index()
    |> Enum.flat_map(fn {point, _idx} ->
      start_sec = Map.get(point, "start", 0.0)
      end_sec = Map.get(point, "end", 4.0)

      case LoopExtractor.extract_loop(file_path, start_sec, end_sec) do
        {:ok, output_path} ->
          [output_path]

        {:error, reason} ->
          Logger.warning("[BigLoopyTrackWorker] Loop extraction failed (#{alchemy_set_id}): #{inspect(reason)}")
          []
      end
    end)
  end
end
