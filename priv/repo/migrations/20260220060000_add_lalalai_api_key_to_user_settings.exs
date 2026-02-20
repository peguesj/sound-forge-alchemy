defmodule SoundForge.Repo.Migrations.AddLalalaiApiKeyToUserSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add :lalalai_api_key, :binary
    end
  end
end
