defmodule SoundForge.Repo.Migrations.CreateSamplePacks do
  use Ecto.Migration

  def change do
    create table(:sample_packs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :integer, on_delete: :delete_all), null: false
      add :name, :string, null: false
      # splice | freesound | local | upload
      add :source, :string, default: "local"
      # drums | bass | synths | vocals | loops | sfx | mixed
      add :category, :string
      add :bpm_range_min, :float
      add :bpm_range_max, :float
      add :key, :string
      add :total_files, :integer, default: 0
      add :manifest_path, :string
      # pending | importing | ready | error
      add :status, :string, null: false, default: "pending"

      timestamps()
    end

    create index(:sample_packs, [:user_id])
    create index(:sample_packs, [:source])
    create index(:sample_packs, [:category])
    create index(:sample_packs, [:status])
  end
end
