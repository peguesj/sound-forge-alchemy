defmodule SoundForge.Repo.Migrations.AddSplicePathToUserSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add :splice_library_path, :string
    end
  end
end
