defmodule SoundForge.Repo.Migrations.ExtendCrateDiggerV2 do
  use Ecto.Migration

  def change do
    # CrateDigger v2: crate collections (folders of crates)
    create table(:crate_collections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :string
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:crate_collections, [:user_id])

    # Extend crates table for v2
    alter table(:crates) do
      # source type: playlist | album | folder | manual
      add :source_type, :string, default: "playlist", null: false
      # collection membership (nullable — a crate can belong to a collection)
      add :collection_id, references(:crate_collections, type: :binary_id, on_delete: :nilify_all)
      # discovered or guided crate profile (BPM range, key prefs, energy range, mood tags)
      add :crate_profile, :map, default: %{}
      # source URLs: for folder crates this is the list of individual playlist URLs
      add :source_urls, {:array, :string}, default: []
    end

    create index(:crates, [:collection_id])
    create index(:crates, [:source_type])
  end
end
