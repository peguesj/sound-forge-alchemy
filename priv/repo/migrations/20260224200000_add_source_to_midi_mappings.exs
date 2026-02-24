defmodule SoundForge.Repo.Migrations.AddSourceToMidiMappings do
  use Ecto.Migration

  def change do
    alter table(:midi_mappings) do
      add :source, :string, null: true
    end
  end
end
