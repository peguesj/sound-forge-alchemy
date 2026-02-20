defmodule SoundForge.Repo.Migrations.CreateMidiMappings do
  use Ecto.Migration

  def change do
    create table(:midi_mappings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :device_name, :string, null: false
      add :midi_type, :string, null: false
      add :channel, :integer, null: false
      add :number, :integer, null: false
      add :action, :string, null: false
      add :params, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:midi_mappings, [:user_id])
    create index(:midi_mappings, [:user_id, :device_name])
    create unique_index(:midi_mappings, [:user_id, :device_name, :midi_type, :channel, :number])
  end
end
