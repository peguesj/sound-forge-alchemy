defmodule SoundForge.Jobs.BigLoopyOrchestratorWorker do
  @moduledoc """
  Oban worker that orchestrates the full BigLoopy pipeline for an AlchemySet.

  Receives `alchemy_set_id`, updates the AlchemySet status to "processing",
  and spawns a BigLoopyTrackWorker job per source track in the set.

  Args:
    - "alchemy_set_id" — UUID of the AlchemySet to process
  """
  use Oban.Worker,
    queue: :big_loopy,
    max_attempts: 3,
    priority: 3

  alias SoundForge.BigLoopy
  alias SoundForge.BigLoopy.Broadcaster

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alchemy_set_id" => alchemy_set_id}}) do
    Logger.metadata(worker: "BigLoopyOrchestratorWorker", alchemy_set_id: alchemy_set_id)
    Logger.info("[BigLoopyOrchestratorWorker] Starting pipeline for #{alchemy_set_id}")

    case BigLoopy.get_alchemy_set(alchemy_set_id) do
      nil ->
        Logger.warning("[BigLoopyOrchestratorWorker] AlchemySet #{alchemy_set_id} not found — skipping")
        :ok

      alchemy_set ->
        BigLoopy.update_status(alchemy_set, "processing")
        Broadcaster.broadcast_started(alchemy_set_id)

        track_ids = alchemy_set.source_track_ids || []

        if track_ids == [] do
          Logger.warning("[BigLoopyOrchestratorWorker] No source tracks in AlchemySet #{alchemy_set_id}")
          BigLoopy.update_status(alchemy_set, "error")
          {:error, :no_source_tracks}
        else
          # Spawn a TrackWorker per source track
          Enum.each(track_ids, fn track_id ->
            {:ok, _job} =
              Oban.insert(
                SoundForge.Jobs.BigLoopyTrackWorker.new(%{
                  "alchemy_set_id" => alchemy_set_id,
                  "track_id" => track_id,
                  "recipe" => alchemy_set.recipe
                })
              )
          end)

          Logger.info("[BigLoopyOrchestratorWorker] Spawned #{length(track_ids)} track workers for #{alchemy_set_id}")
          :ok
        end
    end
  end
end
