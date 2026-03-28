defmodule SoundForge.Repo.Migrations.CreatePerformanceSets do
  use Ecto.Migration

  def change do
    create table(:performance_sets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :track_id, references(:tracks, type: :binary_id, on_delete: :nilify_all), null: true
      add :name, :string, null: false
      add :set_type, :string, null: false, default: "cueset"
      add :source, :string, null: false, default: "chef"
      add :schema_version, :string, null: false, default: "1.0"
      add :items, {:array, :map}, null: false, default: []
      add :metadata, :map, null: false, default: %{}
      add :activated_at, :utc_datetime, null: true
      add :generation_opts, :map, null: false, default: %{}

      timestamps()
    end

    create index(:performance_sets, [:user_id])
    create index(:performance_sets, [:track_id])
    create index(:performance_sets, [:user_id, :inserted_at])
  end
end
