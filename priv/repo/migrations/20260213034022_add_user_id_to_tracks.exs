defmodule SoundForge.Repo.Migrations.AddUserIdToTracks do
  use Ecto.Migration

  def change do
    alter table(:tracks) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    create index(:tracks, [:user_id])
  end
end
