defmodule SoundForge.Repo.Migrations.AddSpliceFieldsToTracks do
  use Ecto.Migration

  def change do
    alter table(:tracks) do
      add :source, :string, default: "manual", null: false
      add :sample_type, :string, default: "full", null: false
      add :drum_categories, {:array, :string}, default: []
      add :bpm, :float
      add :duration_ms, :integer
    end

    create index(:tracks, [:source])
    create index(:tracks, [:sample_type])
    create index(:tracks, [:drum_categories], using: "GIN")
  end
end
