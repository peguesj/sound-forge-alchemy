defmodule SoundForge.Repo.Migrations.CreateUserSettings do
  use Ecto.Migration

  def change do
    create table(:user_settings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Spotify / Downloads
      add :download_quality, :string
      add :audio_format, :string
      add :output_directory, :string

      # YouTube / yt-dlp
      add :ytdlp_search_depth, :integer
      add :ytdlp_preferred_format, :string
      add :ytdlp_bitrate, :string

      # Demucs
      add :demucs_model, :string
      add :demucs_output_format, :string
      add :demucs_device, :string
      add :demucs_timeout, :integer

      # Analysis
      add :analysis_features, {:array, :string}
      add :analyzer_timeout, :integer

      # Storage
      add :storage_path, :string
      add :max_file_age_days, :integer
      add :retention_days, :integer

      # General
      add :tracks_per_page, :integer
      add :max_upload_size, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_settings, [:user_id])
  end
end
