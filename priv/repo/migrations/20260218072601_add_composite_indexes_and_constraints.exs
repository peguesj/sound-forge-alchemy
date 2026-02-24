defmodule SoundForge.Repo.Migrations.AddCompositeIndexesAndConstraints do
  use Ecto.Migration

  def change do
    # Composite indexes for job status queries (track_id + status)
    create index(:download_jobs, [:track_id, :status])
    create index(:processing_jobs, [:track_id, :status])
    create index(:analysis_jobs, [:track_id, :status])

    # Composite indexes for user-scoped track queries
    create index(:tracks, [:user_id, :inserted_at])
    create index(:tracks, [:user_id, :artist])
    create index(:tracks, [:user_id, :album])

    # Full-text search index for track search
    execute(
      "CREATE INDEX idx_tracks_search_gin ON tracks USING gin(to_tsvector('english', coalesce(title, '') || ' ' || coalesce(artist, '')))",
      "DROP INDEX IF EXISTS idx_tracks_search_gin"
    )

    # CHECK constraints for progress fields
    create constraint(:download_jobs, :download_jobs_progress_range, check: "progress >= 0 AND progress <= 100")
    create constraint(:processing_jobs, :processing_jobs_progress_range, check: "progress >= 0 AND progress <= 100")
    create constraint(:analysis_jobs, :analysis_jobs_progress_range, check: "progress >= 0 AND progress <= 100")
  end
end
