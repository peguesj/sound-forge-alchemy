defmodule SoundForge.Repo.Migrations.CreateAlchemySets do
  use Ecto.Migration

  def change do
    create table(:alchemy_sets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :integer, on_delete: :delete_all), null: false
      add :name, :string, null: false
      # loop_set | performance_set | chef_set
      add :type, :string, null: false, default: "loop_set"
      # JSON array of track UUIDs used as sources
      add :source_track_ids, :jsonb, default: "[]"
      # AI recipe text and parsed structure
      add :recipe, :jsonb, default: "{}"
      # wav | mp3 | flac
      add :output_format, :string, default: "wav"
      # pending | processing | complete | error
      add :status, :string, null: false, default: "pending"
      # Path to assembled ZIP file once complete
      add :zip_path, :string
      # Assembled loop/performance data
      add :performance_set, :jsonb, default: "{}"

      timestamps()
    end

    create index(:alchemy_sets, [:user_id])
    create index(:alchemy_sets, [:status])
    create index(:alchemy_sets, [:type])
    create index(:alchemy_sets, [:inserted_at])
  end
end
