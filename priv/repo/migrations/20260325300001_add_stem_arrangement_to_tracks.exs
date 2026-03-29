defmodule SoundForge.Repo.Migrations.AddStemArrangementToTracks do
  use Ecto.Migration

  def change do
    alter table(:tracks) do
      add :stem_arrangement, :map
    end
  end
end
