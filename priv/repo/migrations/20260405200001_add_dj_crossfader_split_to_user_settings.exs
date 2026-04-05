defmodule SoundForge.Repo.Migrations.AddDjCrossfaderSplitToUserSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add :dj_crossfader_split, :boolean, default: false, null: false
    end
  end
end
