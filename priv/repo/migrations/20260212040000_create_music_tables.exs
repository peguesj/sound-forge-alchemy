defmodule SoundForge.Repo.Migrations.CreateMusicTables do
  use Ecto.Migration

  def change do
    # Create tracks table
    create table(:tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :spotify_id, :text
      add :spotify_url, :text
      add :title, :text, null: false
      add :artist, :text
      add :album, :text
      add :album_art_url, :text
      add :duration, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tracks, [:spotify_id])
    create index(:tracks, [:inserted_at])

    # Create download_jobs table
    create table(:download_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "queued"
      add :progress, :integer, default: 0
      add :output_path, :text
      add :file_size, :bigint
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:download_jobs, [:track_id])
    create index(:download_jobs, [:status])
    create index(:download_jobs, [:inserted_at])

    # Create processing_jobs table
    create table(:processing_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :model, :text, default: "htdemucs"
      add :status, :string, null: false, default: "queued"
      add :progress, :integer, default: 0
      add :output_path, :text
      add :options, :map
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:processing_jobs, [:track_id])
    create index(:processing_jobs, [:status])
    create index(:processing_jobs, [:inserted_at])

    # Create analysis_jobs table
    create table(:analysis_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "queued"
      add :progress, :integer, default: 0
      add :results, :map
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:analysis_jobs, [:track_id])
    create index(:analysis_jobs, [:status])
    create index(:analysis_jobs, [:inserted_at])

    # Create stems table
    create table(:stems, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :processing_job_id,
          references(:processing_jobs, type: :binary_id, on_delete: :delete_all), null: false

      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :stem_type, :string, null: false
      add :file_path, :text
      add :file_size, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:stems, [:processing_job_id])
    create index(:stems, [:track_id])
    create index(:stems, [:inserted_at])

    # Create analysis_results table
    create table(:analysis_results, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false

      add :analysis_job_id, references(:analysis_jobs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tempo, :float
      add :key, :text
      add :energy, :float
      add :spectral_centroid, :float
      add :spectral_rolloff, :float
      add :zero_crossing_rate, :float
      add :features, :map

      timestamps(type: :utc_datetime)
    end

    create index(:analysis_results, [:track_id])
    create index(:analysis_results, [:analysis_job_id])
    create index(:analysis_results, [:inserted_at])
  end
end
