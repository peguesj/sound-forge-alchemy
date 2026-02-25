defmodule SoundForge.Jobs.ProviderHealthWorker do
  @moduledoc """
  Oban worker that performs a health check on a single LLM provider
  and updates its `health_status` in the database.

  Enqueued by `SoundForge.Admin.enqueue_health_checks/1`.
  """
  use Oban.Worker, queue: :analysis, max_attempts: 2

  require Logger

  alias SoundForge.LLM.{Client, Providers}

  @impl true
  def perform(%Oban.Job{args: %{"provider_id" => provider_id}}) do
    case Providers.get_provider(provider_id) do
      nil ->
        # Provider deleted between enqueue and execution — not an error
        :ok

      provider ->
        status = check_health(provider)

        case Providers.update_health(provider, status) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("[ProviderHealthWorker] failed to update health for #{provider_id}: #{inspect(reason)}")
            :ok
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp check_health(provider) do
    case Client.ping(provider) do
      :ok -> :healthy
      {:error, :timeout} -> :degraded
      {:error, _} -> :unreachable
    end
  end
end
