defmodule SoundForge.Repo.Migrations.CreateLlmProviders do
  use Ecto.Migration

  def change do
    create table(:llm_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider_type, :string, null: false
      add :name, :string, null: false
      add :api_key, :binary
      add :base_url, :string
      add :default_model, :string
      add :enabled, :boolean, null: false, default: true
      add :priority, :integer
      add :last_health_check_at, :utc_datetime
      add :health_status, :string, null: false, default: "unknown"
      add :config_json, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:llm_providers, [:user_id])
    create unique_index(:llm_providers, [:user_id, :provider_type, :name])
  end
end
