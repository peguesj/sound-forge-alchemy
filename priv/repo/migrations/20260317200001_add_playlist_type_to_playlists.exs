defmodule SoundForge.Repo.Migrations.AddPlaylistTypeToPlaylists do
  use Ecto.Migration

  def change do
    alter table(:playlists) do
      add :playlist_type, :string, default: "manual", null: false
    end

    create index(:playlists, [:source, :playlist_type])
  end
end
