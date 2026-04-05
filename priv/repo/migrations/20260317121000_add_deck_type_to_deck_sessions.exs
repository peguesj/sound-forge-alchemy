defmodule SoundForge.Repo.Migrations.AddDeckTypeToDeckSessions do
  use Ecto.Migration

  def change do
    alter table(:deck_sessions) do
      add :deck_type, :string, default: "full", null: false
    end
  end
end
