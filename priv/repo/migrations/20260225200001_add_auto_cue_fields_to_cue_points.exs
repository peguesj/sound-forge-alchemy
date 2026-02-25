defmodule SoundForge.Repo.Migrations.AddAutoCueFieldsToCuePoints do
  use Ecto.Migration

  def change do
    alter table(:cue_points) do
      add :auto_generated, :boolean, default: false, null: false
      add :confidence, :float
    end

    create index(:cue_points, [:track_id, :auto_generated])
  end
end
