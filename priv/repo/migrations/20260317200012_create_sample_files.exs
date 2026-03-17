defmodule SoundForge.Repo.Migrations.CreateSampleFiles do
  use Ecto.Migration

  def change do
    create table(:sample_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :pack_id, references(:sample_packs, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :file_path, :string, null: false
      add :duration_ms, :integer
      add :bpm, :float
      add :key, :string
      add :file_size, :integer
      # one_shot | loop | texture | fill
      add :sample_type, :string
      # drums | bass | synths | vocals | sfx | misc
      add :category, :string
      # Waveform preview URL (generated on import)
      add :preview_url, :string
      # Extracted tags/labels
      add :tags, :jsonb, default: "[]"

      timestamps()
    end

    create index(:sample_files, [:pack_id])
    create index(:sample_files, [:name])
    create index(:sample_files, [:bpm])
    create index(:sample_files, [:key])
    create index(:sample_files, [:category])
    create index(:sample_files, [:sample_type])
  end
end
