defmodule SoundForge.MusicFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `SoundForge.Music` context.
  """

  @doc """
  Generate a track.
  """
  def track_fixture(attrs \\ %{}) do
    {:ok, track} =
      attrs
      |> Enum.into(%{
        title: "Test Track #{System.unique_integer([:positive])}",
        artist: "Test Artist",
        album: "Test Album",
        duration: 180,
        spotify_id: "spotify_#{System.unique_integer([:positive])}",
        spotify_url: "https://open.spotify.com/track/test"
      })
      |> SoundForge.Music.create_track()

    track
  end

  @doc """
  Generate a playlist.
  """
  def playlist_fixture(attrs \\ %{}) do
    {:ok, playlist} =
      attrs
      |> Enum.into(%{
        name: "Test Playlist #{System.unique_integer([:positive])}",
        description: "A test playlist",
        spotify_id: "sp_playlist_#{System.unique_integer([:positive])}",
        spotify_url: "https://open.spotify.com/playlist/test"
      })
      |> SoundForge.Music.create_playlist()

    playlist
  end

  @doc """
  Generate a download_job.
  """
  def download_job_fixture(attrs \\ %{}) do
    {:ok, download_job} =
      attrs
      |> Enum.into(%{
        status: :queued,
        progress: 0
      })
      |> SoundForge.Music.create_download_job()

    download_job
  end

  @doc """
  Generate a processing_job.
  """
  def processing_job_fixture(attrs \\ %{}) do
    {:ok, processing_job} =
      attrs
      |> Enum.into(%{
        model: "htdemucs",
        status: :queued,
        progress: 0
      })
      |> SoundForge.Music.create_processing_job()

    processing_job
  end

  @doc """
  Generate an analysis_job.
  """
  def analysis_job_fixture(attrs \\ %{}) do
    {:ok, analysis_job} =
      attrs
      |> Enum.into(%{
        status: :queued,
        progress: 0
      })
      |> SoundForge.Music.create_analysis_job()

    analysis_job
  end

  @doc """
  Generate a stem.
  """
  def stem_fixture(attrs \\ %{}) do
    {:ok, stem} =
      attrs
      |> Enum.into(%{
        file_path: "/path/to/stem.wav",
        file_size: 1024 * 1024
      })
      |> SoundForge.Music.create_stem()

    stem
  end

  @doc """
  Generate an analysis_result.
  """
  def analysis_result_fixture(attrs \\ %{}) do
    {:ok, analysis_result} =
      attrs
      |> Enum.into(%{
        tempo: 120.0,
        key: "C major",
        energy: 0.75,
        spectral_centroid: 1500.0,
        spectral_rolloff: 3000.0,
        zero_crossing_rate: 0.05,
        features: %{}
      })
      |> SoundForge.Music.create_analysis_result()

    analysis_result
  end
end
