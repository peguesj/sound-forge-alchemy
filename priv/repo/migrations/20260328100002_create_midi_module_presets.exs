defmodule SoundForge.Repo.Migrations.CreateMidiModulePresets do
  use Ecto.Migration

  def change do
    create table(:midi_module_presets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :module, :string, null: false
      add :name, :string, null: false
      add :is_default, :boolean, default: false
      add :source, :string, default: "custom"
      add :mappings, :map, null: false, default: %{}
      add :layout_metadata, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:midi_module_presets, [:user_id])
    create index(:midi_module_presets, [:user_id, :module])
    create unique_index(:midi_module_presets, [:user_id, :module, :name])
  end
end
