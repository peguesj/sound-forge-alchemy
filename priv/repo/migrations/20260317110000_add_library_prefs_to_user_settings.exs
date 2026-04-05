defmodule SoundForge.Repo.Migrations.AddLibraryPrefsToUserSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add :warn_on_missing_files, :boolean, default: true, null: false
      add :auto_rescan_on_login, :boolean, default: false, null: false
    end
  end
end
