defmodule SoundForge.Repo.Migrations.AddBatchJobIdToProcessingJobs do
  use Ecto.Migration

  def change do
    alter table(:processing_jobs) do
      add :batch_job_id, references(:batch_jobs, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:processing_jobs, [:batch_job_id])
  end
end
