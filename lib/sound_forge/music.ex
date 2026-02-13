defmodule SoundForge.Music do
  @moduledoc """
  The Music context.
  """

  import Ecto.Query, warn: false
  alias SoundForge.Repo

  alias SoundForge.Music.Track
  alias SoundForge.Music.DownloadJob
  alias SoundForge.Music.ProcessingJob
  alias SoundForge.Music.AnalysisJob
  alias SoundForge.Music.Stem
  alias SoundForge.Music.AnalysisResult

  # Track functions

  @doc """
  Returns the list of tracks.

  ## Examples

      iex> list_tracks()
      [%Track{}, ...]

  """
  def list_tracks do
    Repo.all(Track)
  end

  @doc """
  Searches tracks by title or artist.

  Returns a list of tracks where the title or artist matches the given query
  using case-insensitive pattern matching.

  ## Examples

      iex> search_tracks("beatles")
      [%Track{artist: "The Beatles", ...}]

      iex> search_tracks("nonexistent")
      []

  """
  def search_tracks(query) when is_binary(query) and query != "" do
    pattern = "%#{query}%"

    Track
    |> where([t], ilike(t.title, ^pattern) or ilike(t.artist, ^pattern))
    |> Repo.all()
  end

  def search_tracks(_query), do: []

  @doc """
  Gets a single track.

  Raises `Ecto.NoResultsError` if the Track does not exist.

  ## Examples

      iex> get_track!(123)
      %Track{}

      iex> get_track!(456)
      ** (Ecto.NoResultsError)

  """
  def get_track(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} -> {:ok, Repo.get(Track, id)}
      :error -> {:error, :invalid_id}
    end
  end

  def get_track!(id), do: Repo.get!(Track, id)

  @doc """
  Gets a track with preloaded stems and latest analysis result.
  """
  def get_track_with_details!(id) do
    Track
    |> Repo.get!(id)
    |> Repo.preload([:stems, :analysis_results])
  end

  @doc """
  Creates a track.

  ## Examples

      iex> create_track(%{field: value})
      {:ok, %Track{}}

      iex> create_track(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_track(attrs \\ %{}) do
    %Track{}
    |> Track.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a track.

  ## Examples

      iex> update_track(track, %{field: new_value})
      {:ok, %Track{}}

      iex> update_track(track, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_track(%Track{} = track, attrs) do
    track
    |> Track.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a track.

  ## Examples

      iex> delete_track(track)
      {:ok, %Track{}}

      iex> delete_track(track)
      {:error, %Ecto.Changeset{}}

  """
  def delete_track(%Track{} = track) do
    Repo.delete(track)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking track changes.

  ## Examples

      iex> change_track(track)
      %Ecto.Changeset{data: %Track{}}

  """
  def change_track(%Track{} = track, attrs \\ %{}) do
    Track.changeset(track, attrs)
  end

  # DownloadJob functions

  @doc """
  Gets a single download job.

  Raises `Ecto.NoResultsError` if the Download job does not exist.
  """
  def get_download_job!(id), do: Repo.get!(DownloadJob, id)

  @doc """
  Creates a download job.
  """
  def create_download_job(attrs \\ %{}) do
    %DownloadJob{}
    |> DownloadJob.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a download job.
  """
  def update_download_job(%DownloadJob{} = download_job, attrs) do
    download_job
    |> DownloadJob.changeset(attrs)
    |> Repo.update()
  end

  # ProcessingJob functions

  @doc """
  Gets a single processing job.

  Raises `Ecto.NoResultsError` if the Processing job does not exist.
  """
  def get_processing_job!(id), do: Repo.get!(ProcessingJob, id)

  @doc """
  Creates a processing job.
  """
  def create_processing_job(attrs \\ %{}) do
    %ProcessingJob{}
    |> ProcessingJob.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a processing job.
  """
  def update_processing_job(%ProcessingJob{} = processing_job, attrs) do
    processing_job
    |> ProcessingJob.changeset(attrs)
    |> Repo.update()
  end

  # AnalysisJob functions

  @doc """
  Gets a single analysis job.

  Raises `Ecto.NoResultsError` if the Analysis job does not exist.
  """
  def get_analysis_job!(id), do: Repo.get!(AnalysisJob, id)

  @doc """
  Creates an analysis job.
  """
  def create_analysis_job(attrs \\ %{}) do
    %AnalysisJob{}
    |> AnalysisJob.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an analysis job.
  """
  def update_analysis_job(%AnalysisJob{} = analysis_job, attrs) do
    analysis_job
    |> AnalysisJob.changeset(attrs)
    |> Repo.update()
  end

  # Stem functions

  @doc """
  Lists all stems for a given track.
  """
  def list_stems_for_track(track_id) do
    Stem
    |> where([s], s.track_id == ^track_id)
    |> Repo.all()
  end

  @doc """
  Creates a stem.
  """
  def create_stem(attrs \\ %{}) do
    %Stem{}
    |> Stem.changeset(attrs)
    |> Repo.insert()
  end

  # AnalysisResult functions

  @doc """
  Gets the analysis result for a given track.
  """
  def get_analysis_result_for_track(track_id) do
    AnalysisResult
    |> where([ar], ar.track_id == ^track_id)
    |> Repo.one()
  end

  @doc """
  Creates an analysis result.
  """
  def create_analysis_result(attrs \\ %{}) do
    %AnalysisResult{}
    |> AnalysisResult.changeset(attrs)
    |> Repo.insert()
  end
end
