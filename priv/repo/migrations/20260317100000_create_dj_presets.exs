defmodule SoundForge.Repo.Migrations.CreateDjPresets do
  use Ecto.Migration

  def change do
    create table(:dj_presets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :layout_json, :map, null: false
      add :source, :string, default: "manual", null: false
      add :format_version, :string, default: "1.0", null: false

      timestamps()
    end

    create index(:dj_presets, [:user_id])
    create index(:dj_presets, [:user_id, :inserted_at])
  end
end
