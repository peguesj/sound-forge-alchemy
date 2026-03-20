defmodule SoundForge.Repo.Migrations.CreateCrateDiggerTables do
  use Ecto.Migration

  def change do
    create table(:crates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :spotify_playlist_id, :string, null: false
      add :playlist_data, :jsonb, default: "[]"
      add :stem_config, :jsonb, default: "{\"enabled_stems\": [\"vocals\", \"drums\", \"bass\", \"other\"]}"
      add :user_id, references(:users, type: :integer, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:crates, [:user_id])
    create index(:crates, [:spotify_playlist_id])

    create table(:crate_track_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :spotify_track_id, :string, null: false
      add :stem_override, :jsonb
      add :crate_id, references(:crates, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:crate_track_configs, [:crate_id])
    create unique_index(:crate_track_configs, [:crate_id, :spotify_track_id])

    create table(:who_sampled_cache, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :spotify_track_id, :string, null: false
      add :raw_data, :jsonb, default: "[]"
      add :fetched_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:who_sampled_cache, [:spotify_track_id])
  end
end
