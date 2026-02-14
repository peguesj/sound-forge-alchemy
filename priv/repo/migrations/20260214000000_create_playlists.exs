defmodule SoundForge.Repo.Migrations.CreatePlaylists do
  use Ecto.Migration

  def change do
    create table(:playlists, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :description, :text
      add :spotify_id, :text
      add :spotify_url, :text
      add :cover_art_url, :text
      add :user_id, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:playlists, [:spotify_id, :user_id])
    create index(:playlists, [:user_id])

    create table(:playlist_tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :playlist_id, references(:playlists, type: :binary_id, on_delete: :delete_all),
        null: false

      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :position, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:playlist_tracks, [:playlist_id, :track_id])
    create index(:playlist_tracks, [:playlist_id])
    create index(:playlist_tracks, [:track_id])
  end
end
