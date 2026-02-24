defmodule SoundForge.Repo.Migrations.AllowNullProcessingJobOnStems do
  use Ecto.Migration

  def change do
    alter table(:stems) do
      modify :processing_job_id, :binary_id, null: true,
        from: {:binary_id, null: false}
    end
  end
end
