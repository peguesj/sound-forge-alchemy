defmodule SoundForge.Repo.Migrations.CreateChefSets do
  use Ecto.Migration

  def change do
    create table(:chef_sets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      # "cue_set" | "loop_set" | "hot_cue_set"
      add :set_type, :string, null: false, default: "cue_set"
      # "chef" | "manual"
      add :source, :string, null: false, default: "chef"
      add :generation_opts, :map, default: %{}

      timestamps()
    end

    create index(:chef_sets, [:user_id])
    create index(:chef_sets, [:track_id])
    create index(:chef_sets, [:user_id, :track_id])

    create table(:chef_set_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :chef_set_id, references(:chef_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position_ms, :integer, null: false
      add :end_ms, :integer
      add :label, :string
      add :confidence, :float
      # "hot_cue" | "memory_cue" | "loop" | "beat_marker"
      add :item_type, :string, null: false, default: "hot_cue"
      add :color, :string
      add :sort_order, :integer

      timestamps()
    end

    create index(:chef_set_items, [:chef_set_id])
    create index(:chef_set_items, [:chef_set_id, :confidence])
  end
end
