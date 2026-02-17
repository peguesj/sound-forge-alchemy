defmodule SoundForge.Repo.Migrations.AddDebugModeToUserSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add :debug_mode, :boolean, default: false, null: false
    end
  end
end
