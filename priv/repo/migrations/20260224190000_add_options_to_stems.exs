defmodule SoundForge.Repo.Migrations.AddOptionsToStems do
  use Ecto.Migration

  def change do
    alter table(:stems) do
      add :options, :map, default: %{}
    end
  end
end
