defmodule SoundForge.Repo.Migrations.AddEngineAndPreviewToProcessingJobs do
  use Ecto.Migration

  def change do
    alter table(:processing_jobs) do
      add :engine, :string, default: "demucs", null: false
      add :preview, :boolean, default: false
    end

    alter table(:stems) do
      add :source, :string, default: "local", null: false
    end
  end
end
