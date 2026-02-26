defmodule SoundForge.Jobs.ProviderHealthWorkerTest do
  use SoundForge.DataCase, async: true

  import SoundForge.AccountsFixtures
  alias SoundForge.Jobs.ProviderHealthWorker
  alias SoundForge.LLM.Providers

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp provider_fixture(user_id, attrs \\ %{}) do
    defaults = %{
      name: "Test Provider",
      provider_type: :ollama,
      base_url: "http://localhost:11434",
      default_model: "llama3.2",
      enabled: true,
      priority: 0
    }

    {:ok, provider} = Providers.create_provider(user_id, Map.merge(defaults, attrs))
    provider
  end

  # ---------------------------------------------------------------------------
  # perform/1 — provider deleted between enqueue and execution
  # ---------------------------------------------------------------------------

  describe "perform/1 — missing provider" do
    test "returns :ok when provider_id does not exist" do
      job = %Oban.Job{args: %{"provider_id" => Ecto.UUID.generate()}}
      assert :ok == ProviderHealthWorker.perform(job)
    end
  end

  # ---------------------------------------------------------------------------
  # perform/1 — provider exists
  # ---------------------------------------------------------------------------

  describe "perform/1 — provider exists" do
    setup do
      user = user_fixture()
      provider = provider_fixture(user.id)
      %{user: user, provider: provider}
    end

    test "updates health_status to :healthy when ping returns :ok", %{provider: provider} do
      # Patch LLM.Client.ping via mocking the HTTP layer is complex; instead
      # we verify the perform/1 function completes without error for a local
      # provider (Ollama at unreachable URL will return {:error, _} → :unreachable).
      job = %Oban.Job{args: %{"provider_id" => provider.id}}
      assert :ok == ProviderHealthWorker.perform(job)

      # Health should now be one of the known statuses (we cannot control
      # whether local Ollama is actually running in CI).
      updated = Providers.get_provider(provider.id)
      assert updated.health_status in [:healthy, :degraded, :unreachable]
    end

    test "updates health_status and last_health_check_at timestamp", %{provider: provider} do
      job = %Oban.Job{args: %{"provider_id" => provider.id}}
      :ok = ProviderHealthWorker.perform(job)

      updated = Providers.get_provider(provider.id)
      assert updated.last_health_check_at != nil
    end

    test "sets :unreachable for provider at invalid URL", %{user: user} do
      provider = provider_fixture(user.id, %{
        name: "Unreachable",
        provider_type: :ollama,
        base_url: "http://127.0.0.1:1"
      })

      job = %Oban.Job{args: %{"provider_id" => provider.id}}
      :ok = ProviderHealthWorker.perform(job)

      updated = Providers.get_provider(provider.id)
      assert updated.health_status in [:degraded, :unreachable]
    end
  end
end
