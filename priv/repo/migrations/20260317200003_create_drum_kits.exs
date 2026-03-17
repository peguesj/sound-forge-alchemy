defmodule SoundForge.Repo.Migrations.CreateDrumKits do
  use Ecto.Migration

  def change do
    create table(:drum_kits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :user_id, references(:users, type: :integer, on_delete: :delete_all), null: false
      add :source, :string, default: "splice"
      # JSON array of {slot, track_id, label, note} maps
      add :slots, :jsonb, default: "[]"
      # Cached BPM derived from member tracks
      add :bpm, :float
      # Number of pads in the kit (8, 16, etc.)
      add :pad_count, :integer, default: 16
      # Whether this kit is shared/public
      add :is_public, :boolean, default: false

      timestamps()
    end

    create index(:drum_kits, [:user_id])
    create index(:drum_kits, [:source])
    create index(:drum_kits, [:inserted_at])
  end
end
