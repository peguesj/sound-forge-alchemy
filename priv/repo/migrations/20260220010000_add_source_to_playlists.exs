defmodule SoundForge.Repo.Migrations.AddSourceToPlaylists do
  use Ecto.Migration

  def change do
    alter table(:playlists) do
      add :source, :string, default: "manual", null: false
    end

    execute(
      "UPDATE playlists SET source = 'spotify' WHERE spotify_id IS NOT NULL",
      "UPDATE playlists SET source = 'manual'"
    )
  end
end
