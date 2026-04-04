defmodule SoundForge.Jobs.CrateProfileWorker do
  @moduledoc """
  Oban worker that auto-computes the crate profile using SimilarityEngine.

  Enqueue after a crate is loaded/refreshed to populate `crate_profile` with
  BPM cluster, key distribution, and energy statistics derived from stored
  AnalysisResult records.

  ## Args
    - `"crate_id"` — UUID of the crate to profile
  """
  use Oban.Worker,
    queue: :analysis,
    max_attempts: 3,
    priority: 3

  require Logger

  alias SoundForge.CrateDigger
  alias SoundForge.CrateDigger.SimilarityEngine

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"crate_id" => crate_id}}) do
    crate = CrateDigger.get_crate(crate_id)

    if is_nil(crate) do
      Logger.warning("CrateProfileWorker: crate #{crate_id} not found")
      {:cancel, :crate_not_found}
    else
      case SimilarityEngine.compute_crate_profile(crate) do
        {:ok, profile} ->
          case CrateDigger.update_crate(crate, %{crate_profile: profile}) do
            {:ok, _updated} ->
              Logger.info("CrateProfileWorker: profiled crate #{crate_id} — #{inspect(profile)}")
              :ok

            {:error, changeset} ->
              Logger.error("CrateProfileWorker: save failed — #{inspect(changeset.errors)}")
              {:error, :save_failed}
          end

        {:error, :insufficient_data} ->
          Logger.debug("CrateProfileWorker: crate #{crate_id} has insufficient analysis data")
          # Not an error — reschedule is pointless until more tracks are analyzed
          {:cancel, :insufficient_data}
      end
    end
  end
end
