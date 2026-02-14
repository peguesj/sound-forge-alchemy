defmodule SoundForge.Repo.Migrations.CreateSpotifyOauthTokens do
  use Ecto.Migration

  def change do
    create table(:spotify_oauth_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :access_token, :binary, null: false
      add :refresh_token, :binary, null: false
      add :token_type, :string, default: "Bearer"
      add :expires_at, :utc_datetime, null: false
      add :scopes, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:spotify_oauth_tokens, [:user_id])
  end
end
