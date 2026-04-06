defmodule SoundForge.Repo.Migrations.AddAutoVerifyOnLibraryOpenToUserSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add :auto_verify_on_library_open, :boolean, default: false, null: false
    end
  end
end
