defmodule SoundForge.Repo.Migrations.AddUniqueIndexesStemsAnalysis do
  use Ecto.Migration

  def up do
    # Deduplicate existing stems before adding the unique index
    execute """
    DELETE FROM stems
    WHERE id NOT IN (
      SELECT DISTINCT ON (track_id, stem_type) id
      FROM stems
      ORDER BY track_id, stem_type, inserted_at DESC
    )
    """

    # Deduplicate existing analysis results before adding the unique index
    execute """
    DELETE FROM analysis_results
    WHERE id NOT IN (
      SELECT DISTINCT ON (track_id) id
      FROM analysis_results
      ORDER BY track_id, inserted_at DESC
    )
    """

    # Drop existing non-unique analysis_results_track_id_index before creating unique one
    drop_if_exists index(:analysis_results, [:track_id])

    create unique_index(:stems, [:track_id, :stem_type])
    create unique_index(:analysis_results, [:track_id])
  end

  def down do
    drop_if_exists unique_index(:analysis_results, [:track_id])
    drop_if_exists unique_index(:stems, [:track_id, :stem_type])

    # Restore the original non-unique index
    create index(:analysis_results, [:track_id])
  end
end
