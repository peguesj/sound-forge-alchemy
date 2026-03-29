defmodule SoundForge.Repo.Migrations.AddStepsToStemLoops do
  use Ecto.Migration

  def change do
    alter table(:stem_loops) do
      add :steps, {:array, :boolean}, default: [true, true, true, true, true, true, true, true]
    end
  end
end
