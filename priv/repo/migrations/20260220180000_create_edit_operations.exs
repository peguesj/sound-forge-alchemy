defmodule SoundForge.Repo.Migrations.CreateEditOperations do
  use Ecto.Migration

  def change do
    create table(:edit_operations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :stem_id, references(:stems, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :delete_all),
        null: false

      add :operation_type, :string, null: false
      add :params, :map, null: false, default: %{}
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:edit_operations, [:stem_id])
    create index(:edit_operations, [:user_id])
    create index(:edit_operations, [:stem_id, :position])
  end
end
