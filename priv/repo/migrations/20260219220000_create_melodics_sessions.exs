defmodule SoundForge.Repo.Migrations.CreateMelodicsSessions do
  use Ecto.Migration

  def change do
    create table(:melodics_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :lesson_name, :string, null: false
      add :accuracy, :float
      add :bpm, :integer
      add :instrument, :string
      add :practiced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:melodics_sessions, [:user_id])
    create index(:melodics_sessions, [:practiced_at])
  end
end
