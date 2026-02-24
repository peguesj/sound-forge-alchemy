defmodule SoundForge.Repo.Migrations.CreateDjTables do
  use Ecto.Migration

  def change do
    # Create cue_points table
    create table(:cue_points, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :position_ms, :integer, null: false
      add :label, :string
      add :color, :string
      add :cue_type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:cue_points, [:track_id])
    create index(:cue_points, [:user_id])
    create index(:cue_points, [:track_id, :cue_type])

    # Create deck_sessions table
    create table(:deck_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :deck_number, :integer, null: false
      add :track_id, references(:tracks, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :tempo_bpm, :float
      add :pitch_adjust, :float, default: 0.0
      add :loop_start_ms, :integer
      add :loop_end_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:deck_sessions, [:user_id])
    create unique_index(:deck_sessions, [:user_id, :deck_number])
  end
end
