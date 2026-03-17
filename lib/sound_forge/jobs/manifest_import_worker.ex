defmodule SoundForge.Jobs.ManifestImportWorker do
  @moduledoc """
  Oban worker that imports a sample pack manifest file in the background.

  Accepts args:
    - "pack_id"        — UUID of the SamplePack to populate
    - "manifest_path"  — Absolute path to a JSON manifest file

  On success, broadcasts {:sample_library, :import_complete, pack_id} via PubSub.
  On failure, updates pack status to "error" and re-raises.
  """
  use Oban.Worker,
    queue: :processing,
    max_attempts: 3,
    priority: 5

  alias SoundForge.SampleLibrary

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"pack_id" => pack_id, "manifest_path" => manifest_path}}) do
    Logger.metadata(worker: "ManifestImportWorker", pack_id: pack_id)
    Logger.info("[ManifestImportWorker] Starting import for pack #{pack_id} from #{manifest_path}")

    case SampleLibrary.get_pack(pack_id) do
      nil ->
        Logger.warning("[ManifestImportWorker] Pack #{pack_id} not found — skipping")
        :ok

      pack ->
        # Mark as importing
        SampleLibrary.update_pack(pack, %{status: "importing"})

        case SampleLibrary.import_from_manifest(pack, manifest_path) do
          {:ok, count} ->
            Logger.info("[ManifestImportWorker] Imported #{count} files into pack #{pack.name}")

            # Broadcast completion
            Phoenix.PubSub.broadcast(
              SoundForge.PubSub,
              "sample_library:#{pack_id}",
              {:sample_library, :import_complete, pack_id}
            )

            :ok

          {:error, reason} ->
            Logger.warning("[ManifestImportWorker] Import failed: #{inspect(reason)}")

            # Refresh pack from DB before updating (may have changed)
            fresh_pack = SampleLibrary.get_pack(pack_id) || pack
            SampleLibrary.update_pack(fresh_pack, %{status: "error"})

            {:error, reason}
        end
    end
  end
end
