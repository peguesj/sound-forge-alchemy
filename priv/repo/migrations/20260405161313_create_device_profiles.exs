defmodule SoundForge.Repo.Migrations.CreateDeviceProfiles do
  use Ecto.Migration

  def change do
    create table(:device_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :vendor, :string
      add :source, :string, null: false
      add :device_id, :string
      add :mappings, :map, default: %{}
      add :user_id, references(:users, type: :integer, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:device_profiles, [:user_id])
    create index(:device_profiles, [:device_id])
    create index(:device_profiles, [:source])
  end
end
