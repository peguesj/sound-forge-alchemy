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
  Returns the list of tracks, optionally scoped to a user.
  """
  def list_tracks(opts \\ [])

  def list_tracks(opts) when is_list(opts) do
    Track
    |> apply_sort(opts)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  def list_tracks(%{user: %{id: _user_id}} = scope) do
    list_tracks(scope, [])
  end

  def list_tracks(%{user: %{id: user_id}}, opts) when is_list(opts) do
    Track
    |> where([t], t.user_id == ^user_id)
    |> apply_sort(opts)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc """
  Returns the total count of tracks, optionally scoped to a user.
  """
  def count_tracks do
    Repo.aggregate(Track, :count)
  end

  def count_tracks(%{user: %{id: user_id}}) do
    Track
    |> where([t], t.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  defp apply_pagination(query, opts) do
    per_page = Keyword.get(opts, :per_page)
    page = Keyword.get(opts, :page, 1)

    if per_page do
      offset = (page - 1) * per_page

      query
      |> limit(^per_page)
      |> offset(^offset)
    else
      query
    end
  end

  defp apply_sort(query, opts) do
    case Keyword.get(opts, :sort_by) do
      :title -> order_by(query, [t], asc: t.title)
      :artist -> order_by(query, [t], asc: t.artist)
      :duration -> order_by(query, [t], desc: t.duration)
      :newest -> order_by(query, [t], desc: t.inserted_at)
      :oldest -> order_by(query, [t], asc: t.inserted_at)
      _ -> order_by(query, [t], desc: t.inserted_at)
    end
  end

  @doc """
  Searches tracks by title or artist, optionally scoped to a user.
  """
  def search_tracks(query) when is_binary(query) and query != "" do
    pattern = "%#{query}%"

    Track
    |> where([t], ilike(t.title, ^pattern) or ilike(t.artist, ^pattern))
    |> Repo.all()
  end

  def search_tracks(_query), do: []

  def search_tracks(query, %{user: %{id: user_id}}) when is_binary(query) and query != "" do
    pattern = "%#{query}%"

    Track
    |> where([t], t.user_id == ^user_id)
    |> where([t], ilike(t.title, ^pattern) or ilike(t.artist, ^pattern))
    |> Repo.all()
  end

  def search_tracks(_query, _scope), do: []

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
  Gets a track by its Spotify ID. Returns nil if not found.
  """
  def get_track_by_spotify_id(spotify_id) when is_binary(spotify_id) do
    Repo.get_by(Track, spotify_id: spotify_id)
  end

  def get_track_by_spotify_id(_), do: nil

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
  Deletes a track and cleans up all associated files from storage.
  """
  def delete_track_with_files(%Track{} = track) do
    track = Repo.preload(track, [:stems, :download_jobs])

    # Collect file paths to clean up
    stem_paths = Enum.map(track.stems, & &1.file_path) |> Enum.filter(& &1)

    download_paths =
      Enum.map(track.download_jobs, & &1.output_path) |> Enum.filter(& &1)

    # Delete the track (cascades to jobs, stems, results via DB)
    case Repo.delete(track) do
      {:ok, deleted_track} ->
        # Clean up files after successful DB delete
        Enum.each(stem_paths ++ download_paths, fn path ->
          full_path =
            if String.starts_with?(path, "/") do
              path
            else
              Path.join(SoundForge.Storage.base_path(), path)
            end

          File.rm(full_path)
        end)

        {:ok, deleted_track}

      error ->
        error
    end
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
  Gets a single stem.
  """
  def get_stem!(id), do: Repo.get!(Stem, id)

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
