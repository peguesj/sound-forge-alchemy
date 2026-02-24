defmodule SoundForge.Repo.Migrations.CreateBatchJobsAndVoicePacks do
  use Ecto.Migration

  def change do
    # Create batch_jobs table for grouping multiple processing jobs
    create table(:batch_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :total_count, :integer, null: false
      add :completed_count, :integer, null: false, default: 0
      add :options, :map

      timestamps(type: :utc_datetime)
    end

    create index(:batch_jobs, [:user_id])
    create index(:batch_jobs, [:status])
    create index(:batch_jobs, [:inserted_at])

    # Create voice_packs table for caching voice pack metadata
    create table(:voice_packs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :pack_id, :string, null: false
      add :name, :string, null: false
      add :created_at_remote, :utc_datetime
      add :cached_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:voice_packs, [:pack_id])
    create index(:voice_packs, [:inserted_at])
  end
end
