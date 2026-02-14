defmodule SoundForge.Repo.Migrations.FixEmptyAlbumStrings do
  use Ecto.Migration

  def up do
    execute "UPDATE tracks SET album = NULL WHERE album = ''"
  end

  def down do
    # No rollback needed - empty strings and NULL are both "no album"
    :ok
  end
end
