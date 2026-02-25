defmodule SoundForge.Repo.Migrations.CreateStemLoops do
  use Ecto.Migration

  def change do
    create table(:stem_loops, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stem_id, references(:stems, type: :binary_id, on_delete: :delete_all), null: false
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :label, :string
      add :start_ms, :integer, null: false
      add :end_ms, :integer, null: false
      add :color, :string

      timestamps(type: :utc_datetime)
    end

    create index(:stem_loops, [:stem_id])
    create index(:stem_loops, [:track_id])
    create index(:stem_loops, [:user_id])
    create index(:stem_loops, [:track_id, :user_id])
  end
end
