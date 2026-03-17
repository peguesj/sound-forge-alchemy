# Seed Azure OpenAI providers for admin+ users.
#
#   mix run priv/repo/seeds_llm_providers.exs
#
# Uses the AZURE_OPENAI_API_KEY env var (must be sourced before running).
# All 5 models deployed on the claude-code-proxy-aoai resource (eastus2).

alias SoundForge.Repo
alias SoundForge.Accounts.User
alias SoundForge.LLM.Provider

import Ecto.Query

azure_key = System.get_env("AZURE_OPENAI_API_KEY")
azure_endpoint = "https://claude-code-proxy-aoai.openai.azure.com/"

unless azure_key do
  IO.puts("AZURE_OPENAI_API_KEY not set — skipping LLM provider seeds.")
  System.halt(0)
end

providers = [
  %{
    provider_type: :azure_openai,
    name: "Azure GPT-5.2 (eastus2)",
    api_key: azure_key,
    base_url: azure_endpoint,
    default_model: "gpt-5-2",
    priority: 1,
    config_json: %{"api_version" => "2025-04-01-preview", "deployment" => "gpt-5-2", "region" => "eastus2"}
  },
  %{
    provider_type: :azure_openai,
    name: "Azure GPT-4.1 (eastus2)",
    api_key: azure_key,
    base_url: azure_endpoint,
    default_model: "gpt-4-1",
    priority: 2,
    config_json: %{"api_version" => "2025-04-01-preview", "deployment" => "gpt-4-1", "region" => "eastus2"}
  },
  %{
    provider_type: :azure_openai,
    name: "Azure o4-mini (eastus2)",
    api_key: azure_key,
    base_url: azure_endpoint,
    default_model: "o4-mini",
    priority: 3,
    config_json: %{"api_version" => "2025-04-01-preview", "deployment" => "o4-mini", "region" => "eastus2"}
  },
  %{
    provider_type: :azure_openai,
    name: "Azure GPT-4o (eastus2)",
    api_key: azure_key,
    base_url: azure_endpoint,
    default_model: "gpt-4o",
    priority: 4,
    config_json: %{"api_version" => "2025-04-01-preview", "deployment" => "gpt-4o", "region" => "eastus2"}
  },
  %{
    provider_type: :azure_openai,
    name: "Azure GPT-5 mini (eastus2)",
    api_key: azure_key,
    base_url: azure_endpoint,
    default_model: "gpt-5-mini",
    priority: 5,
    config_json: %{"api_version" => "2025-04-01-preview", "deployment" => "gpt-5-mini", "region" => "eastus2"}
  }
]

# Seed for all admin+ users
admin_roles = [:admin, :super_admin, :platform_admin]

admin_users =
  from(u in User, where: u.role in ^admin_roles)
  |> Repo.all()

if admin_users == [] do
  IO.puts("No admin users found — run seeds.exs first.")
  System.halt(1)
end

for user <- admin_users do
  for attrs <- providers do
    attrs = Map.put(attrs, :user_id, user.id)

    %Provider{}
    |> Provider.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:api_key, :base_url, :default_model, :config_json, :updated_at]},
      conflict_target: [:user_id, :provider_type, :name]
    )
    |> case do
      {:ok, p} -> IO.puts("  #{user.email} -> #{p.name} (#{p.default_model})")
      {:error, cs} -> IO.puts("  SKIP #{user.email} #{attrs.name}: #{inspect(cs.errors)}")
    end
  end
end

IO.puts("\nDone. #{length(admin_users)} admin users x #{length(providers)} providers.")
