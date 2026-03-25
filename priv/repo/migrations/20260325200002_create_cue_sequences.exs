defmodule SoundForge.Repo.Migrations.CreateCueSequences do
  use Ecto.Migration

  def change do
    create table(:cue_sequences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :step_count, :integer, null: false, default: 16
      add :step_cues, {:array, :string}, default: []
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:cue_sequences, [:track_id, :user_id])
  end
end
