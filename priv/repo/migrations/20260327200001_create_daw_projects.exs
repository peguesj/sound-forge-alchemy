defmodule SoundForge.Repo.Migrations.CreateDawProjects do
  use Ecto.Migration

  def change do
    create table(:daw_projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :integer, on_delete: :delete_all), null: false
      add :title, :string, null: false, default: "Untitled Project"
      add :bpm, :integer, default: 120
      add :key, :string
      add :time_sig, :string, default: "4/4"
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:daw_projects, [:user_id])

    create table(:daw_project_tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :daw_project_id,
          references(:daw_projects, type: :binary_id, on_delete: :delete_all),
          null: false

      add :audio_file_id, references(:tracks, type: :binary_id, on_delete: :nilify_all)
      add :title, :string
      add :position, :integer, null: false, default: 0
      add :track_type, :string, null: false, default: "unknown"
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:daw_project_tracks, [:daw_project_id])
    create index(:daw_project_tracks, [:daw_project_id, :position])
  end
end
