defmodule SoundForge.Music do
  @moduledoc """
  The Music context.
  """

  import Ecto.Query, warn: false
  alias SoundForge.Repo

  alias SoundForge.Music.AnalysisJob
  alias SoundForge.Music.AnalysisResult
  alias SoundForge.Music.DownloadJob
  alias SoundForge.Music.Playlist
  alias SoundForge.Music.PlaylistTrack
  alias SoundForge.Music.ProcessingJob
  alias SoundForge.Music.Stem
  alias SoundForge.Music.Track

  @type scope :: %{user: %{id: term()}}

  # Track functions

  @doc """
  Returns the list of tracks, optionally scoped to a user.
  """
  @spec list_tracks(keyword()) :: [Track.t()]
  @spec list_tracks(scope()) :: [Track.t()]
  def list_tracks(opts \\ [])

  def list_tracks(opts) when is_list(opts) do
    Track
    |> apply_filters(opts)
    |> apply_sort(opts)
    |> apply_pagination(opts)
    |> with_download_status()
    |> Repo.all()
  end

  def list_tracks(%{user: %{id: _user_id}} = scope) do
    list_tracks(scope, [])
  end

  def list_tracks(%{user: %{id: user_id}}, opts) when is_list(opts) do
    Track
    |> where([t], t.user_id == ^user_id)
    |> apply_filters(opts)
    |> apply_sort(opts)
    |> apply_pagination(opts)
    |> with_download_status()
    |> Repo.all()
  end

  @doc """
  Returns the total count of tracks, optionally scoped to a user.
  """
  @spec count_tracks() :: non_neg_integer()
  def count_tracks do
    Repo.aggregate(Track, :count)
  end

  @spec count_tracks(scope()) :: non_neg_integer()
  def count_tracks(%{user: %{id: user_id}}) do
    Track
    |> where([t], t.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  defp apply_filters(query, opts) do
    filters = Keyword.get(opts, :filters, %{})

    query
    |> apply_status_filter(Map.get(filters, :status, "all"))
    |> apply_artist_filter(Map.get(filters, :artist, "all"))
    |> apply_album_filter(Map.get(filters, :album))
  end

  defp apply_status_filter(query, "all"), do: query

  defp apply_status_filter(query, "pending") do
    query
    |> where(
      [t],
      fragment(
        "NOT EXISTS (SELECT 1 FROM download_jobs WHERE download_jobs.track_id = ? AND download_jobs.status = 'completed')",
        t.id
      )
    )
  end

  defp apply_status_filter(query, "downloaded") do
    query
    |> where(
      [t],
      fragment(
        "EXISTS (SELECT 1 FROM download_jobs WHERE download_jobs.track_id = ? AND download_jobs.status = 'completed')",
        t.id
      )
    )
  end

  defp apply_status_filter(query, "processed") do
    query
    |> where(
      [t],
      fragment("EXISTS (SELECT 1 FROM stems WHERE stems.track_id = ?)", t.id)
    )
  end

  defp apply_status_filter(query, "analyzed") do
    query
    |> where(
      [t],
      fragment(
        "EXISTS (SELECT 1 FROM analysis_results WHERE analysis_results.track_id = ?)",
        t.id
      )
    )
  end

  defp apply_status_filter(query, _), do: query

  defp apply_artist_filter(query, "all"), do: query

  defp apply_artist_filter(query, artist) when is_binary(artist) and artist != "" do
    where(query, [t], t.artist == ^artist)
  end

  defp apply_artist_filter(query, _), do: query

  defp apply_album_filter(query, nil), do: query

  defp apply_album_filter(query, album) when is_binary(album) and album != "" do
    where(query, [t], t.album == ^album)
  end

  defp apply_album_filter(query, _), do: query

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

  defp with_download_status(query) do
    from(t in query,
      select_merge: %{
        download_status:
          fragment(
            "(SELECT status FROM download_jobs WHERE track_id = ? ORDER BY inserted_at DESC LIMIT 1)",
            t.id
          )
      }
    )
  end

  @doc """
  Searches tracks by title or artist, optionally scoped to a user.
  """
  @spec search_tracks(String.t()) :: [Track.t()]
  def search_tracks(query) when is_binary(query) and query != "" do
    pattern = "%#{query}%"

    Track
    |> where([t], ilike(t.title, ^pattern) or ilike(t.artist, ^pattern))
    |> Repo.all()
  end

  def search_tracks(_query), do: []

  @spec search_tracks(String.t(), scope()) :: [Track.t()]
  def search_tracks(query, %{user: %{id: user_id}}) when is_binary(query) and query != "" do
    pattern = "%#{query}%"

    Track
    |> where([t], t.user_id == ^user_id)
    |> where([t], ilike(t.title, ^pattern) or ilike(t.artist, ^pattern))
    |> Repo.all()
  end

  def search_tracks(_query, _scope), do: []

  @doc """
  Returns distinct artist names for the given user scope.
  """
  @spec list_distinct_artists(scope()) :: [String.t()]
  def list_distinct_artists(%{user: %{id: user_id}}) do
    Track
    |> where([t], t.user_id == ^user_id and not is_nil(t.artist))
    |> select([t], t.artist)
    |> distinct(true)
    |> order_by([t], asc: t.artist)
    |> Repo.all()
  end

  @spec list_distinct_artists() :: [String.t()]
  def list_distinct_artists do
    Track
    |> where([t], not is_nil(t.artist))
    |> select([t], t.artist)
    |> distinct(true)
    |> order_by([t], asc: t.artist)
    |> Repo.all()
  end

  @doc """
  Gets a single track.

  Raises `Ecto.NoResultsError` if the Track does not exist.

  ## Examples

      iex> get_track!(123)
      %Track{}

      iex> get_track!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_track(String.t()) :: {:ok, Track.t() | nil} | {:error, :invalid_id}
  def get_track(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} -> {:ok, Repo.get(Track, id)}
      :error -> {:error, :invalid_id}
    end
  end

  @spec get_track!(String.t()) :: Track.t()
  def get_track!(id), do: Repo.get!(Track, id)

  @doc """
  Gets a track by its Spotify ID. Returns nil if not found.
  """
  @spec get_track_by_spotify_id(String.t() | nil) :: Track.t() | nil
  def get_track_by_spotify_id(spotify_id) when is_binary(spotify_id) do
    Repo.get_by(Track, spotify_id: spotify_id)
  end

  def get_track_by_spotify_id(_), do: nil

  @doc """
  Gets a track with preloaded stems, download_jobs, and latest analysis result.
  """
  @spec get_track_with_details!(String.t()) :: Track.t()
  def get_track_with_details!(id) do
    Track
    |> where([t], t.id == ^id)
    |> with_download_status()
    |> Repo.one!()
    |> Repo.preload([:stems, :analysis_results, :download_jobs])
  end

  @doc """
  Creates a track.

  ## Examples

      iex> create_track(%{field: value})
      {:ok, %Track{}}

      iex> create_track(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_track(map()) :: {:ok, Track.t()} | {:error, Ecto.Changeset.t()}
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
  @spec update_track(Track.t(), map()) :: {:ok, Track.t()} | {:error, Ecto.Changeset.t()}
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
  @spec delete_track(Track.t()) :: {:ok, Track.t()} | {:error, Ecto.Changeset.t()}
  def delete_track(%Track{} = track) do
    # Clean up any lalal.ai source files before deleting the track record
    track
    |> Repo.preload(:processing_jobs)
    |> Map.get(:processing_jobs, [])
    |> Enum.each(fn job ->
      case get_in(job.options, ["lalalai_source_id"]) do
        nil -> :ok
        source_id -> SoundForge.Audio.LalalAI.delete_source(source_id)
      end
    end)

    Repo.delete(track)
  end

  @doc """
  Deletes a track and cleans up all associated files from storage.
  """
  @spec delete_track_with_files(Track.t()) :: {:ok, Track.t()} | {:error, Ecto.Changeset.t()}
  def delete_track_with_files(%Track{} = track) do
    track = Repo.preload(track, [:stems, :download_jobs])

    # Collect file paths to clean up
    stem_paths = Enum.map(track.stems, & &1.file_path) |> Enum.filter(& &1)

    download_paths =
      Enum.map(track.download_jobs, & &1.output_path) |> Enum.filter(& &1)

    # Delete the track (cascades to jobs, stems, results via DB)
    case Repo.delete(track) do
      {:ok, deleted_track} ->
        cleanup_file_paths(stem_paths ++ download_paths)
        {:ok, deleted_track}

      error ->
        error
    end
  end

  defp cleanup_file_paths(paths) do
    Enum.each(paths, fn path ->
      full_path = resolve_file_path(path)
      File.rm(full_path)
    end)
  end

  defp resolve_file_path(path) do
    if String.starts_with?(path, "/"),
      do: path,
      else: Path.join(SoundForge.Storage.base_path(), path)
  end

  @doc "Returns the number of stems for a given track."
  @spec count_stems(binary()) :: non_neg_integer()
  def count_stems(track_id) do
    Repo.aggregate(from(s in Stem, where: s.track_id == ^track_id), :count)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking track changes.

  ## Examples

      iex> change_track(track)
      %Ecto.Changeset{data: %Track{}}

  """
  @spec change_track(Track.t(), map()) :: Ecto.Changeset.t()
  def change_track(%Track{} = track, attrs \\ %{}) do
    Track.changeset(track, attrs)
  end

  # Playlist functions

  @doc "Lists playlists for a user scope, ordered by name."
  @spec list_playlists(scope()) :: [Playlist.t()]
  def list_playlists(%{user: %{id: user_id}}) do
    Playlist
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc "Lists playlists grouped by source field for smart folder rendering."
  @spec list_playlists_grouped_by_source(scope()) :: %{String.t() => [Playlist.t()]}
  def list_playlists_grouped_by_source(scope) do
    list_playlists(scope)
    |> Enum.group_by(& &1.source)
    |> Map.put_new("spotify", [])
    |> Map.put_new("manual", [])
  end

  @doc "Gets a single playlist with preloaded tracks."
  @spec get_playlist!(String.t()) :: Playlist.t()
  def get_playlist!(id) do
    Playlist
    |> Repo.get!(id)
    |> Repo.preload(playlist_tracks: {from(pt in PlaylistTrack, order_by: pt.position), :track})
  end

  @doc "Gets a playlist by Spotify ID and user ID."
  @spec get_playlist_by_spotify_id(String.t(), term()) :: Playlist.t() | nil
  def get_playlist_by_spotify_id(spotify_id, user_id) when is_binary(spotify_id) do
    Repo.get_by(Playlist, spotify_id: spotify_id, user_id: user_id)
  end

  def get_playlist_by_spotify_id(_, _), do: nil

  @doc "Creates a playlist."
  @spec create_playlist(map()) :: {:ok, Playlist.t()} | {:error, Ecto.Changeset.t()}
  def create_playlist(attrs \\ %{}) do
    %Playlist{}
    |> Playlist.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a playlist."
  @spec update_playlist(Playlist.t(), map()) :: {:ok, Playlist.t()} | {:error, Ecto.Changeset.t()}
  def update_playlist(%Playlist{} = playlist, attrs) do
    playlist
    |> Playlist.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a playlist."
  @spec delete_playlist(Playlist.t()) :: {:ok, Playlist.t()} | {:error, Ecto.Changeset.t()}
  def delete_playlist(%Playlist{} = playlist) do
    Repo.delete(playlist)
  end

  @doc "Adds a track to a playlist at the given position."
  @spec add_track_to_playlist(Playlist.t(), Track.t(), integer()) ::
          {:ok, PlaylistTrack.t()} | {:error, Ecto.Changeset.t()}
  def add_track_to_playlist(%Playlist{} = playlist, %Track{} = track, position \\ 0) do
    %PlaylistTrack{}
    |> PlaylistTrack.changeset(%{
      playlist_id: playlist.id,
      track_id: track.id,
      position: position
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc "Removes a track from a playlist."
  @spec remove_track_from_playlist(Playlist.t(), Track.t()) :: {non_neg_integer(), nil}
  def remove_track_from_playlist(%Playlist{} = playlist, %Track{} = track) do
    PlaylistTrack
    |> where([pt], pt.playlist_id == ^playlist.id and pt.track_id == ^track.id)
    |> Repo.delete_all()
  end

  @doc "Lists tracks for a specific playlist with pagination."
  @spec list_tracks_for_playlist(String.t(), keyword()) :: [Track.t()]
  def list_tracks_for_playlist(playlist_id, opts \\ []) do
    Track
    |> join(:inner, [t], pt in PlaylistTrack,
      on: pt.track_id == t.id and pt.playlist_id == ^playlist_id
    )
    |> order_by([t, pt], asc: pt.position)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc "Returns distinct album names for the given user scope."
  @spec list_distinct_albums(scope()) :: [String.t()]
  def list_distinct_albums(%{user: %{id: user_id}}) do
    Track
    |> where([t], t.user_id == ^user_id and not is_nil(t.album) and t.album != "")
    |> select([t], t.album)
    |> distinct(true)
    |> order_by([t], asc: t.album)
    |> Repo.all()
  end

  # DownloadJob functions

  @doc """
  Gets a single download job.

  Raises `Ecto.NoResultsError` if the Download job does not exist.
  """
  @spec get_download_job!(String.t()) :: DownloadJob.t()
  def get_download_job!(id), do: Repo.get!(DownloadJob, id)

  @doc """
  Creates a download job.
  """
  @spec create_download_job(map()) :: {:ok, DownloadJob.t()} | {:error, Ecto.Changeset.t()}
  def create_download_job(attrs \\ %{}) do
    %DownloadJob{}
    |> DownloadJob.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets the output path of the latest completed download job for a track.
  Returns `{:ok, path}` or `{:error, :no_completed_download}`.
  """
  @spec get_download_path(String.t()) :: {:ok, String.t()} | {:error, :no_completed_download}
  def get_download_path(track_id) do
    query =
      from dj in DownloadJob,
        where:
          dj.track_id == ^track_id and dj.status == :completed and not is_nil(dj.output_path),
        order_by: [desc: dj.updated_at],
        limit: 1,
        select: dj.output_path

    case Repo.one(query) do
      nil -> {:error, :no_completed_download}
      path -> {:ok, path}
    end
  end

  @doc """
  Gets the download path for a track and validates that the file exists.

  Returns `{:ok, path}` if file exists and is valid, or `{:error, reason}`.
  Useful for pre-flight checks before processing/playing audio.
  """
  @spec get_download_path_validated(String.t()) ::
          {:ok, String.t()} | {:error, :no_completed_download | String.t()}
  def get_download_path_validated(track_id) do
    with {:ok, path} <- get_download_path(track_id),
         {:ok, resolved_path} <- SoundForge.Storage.validate_download_path(path) do
      {:ok, resolved_path}
    else
      {:error, :no_completed_download} = err -> err
      {:error, validation_error} -> {:error, "File validation failed: #{validation_error}"}
    end
  end

  @doc """
  Updates a download job.
  """
  @spec update_download_job(DownloadJob.t(), map()) ::
          {:ok, DownloadJob.t()} | {:error, Ecto.Changeset.t()}
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
  @spec get_processing_job!(String.t()) :: ProcessingJob.t()
  def get_processing_job!(id), do: Repo.get!(ProcessingJob, id)

  @doc """
  Creates a processing job.
  """
  @spec create_processing_job(map()) :: {:ok, ProcessingJob.t()} | {:error, Ecto.Changeset.t()}
  def create_processing_job(attrs \\ %{}) do
    attrs = ensure_idempotency_key(attrs)

    %ProcessingJob{}
    |> ProcessingJob.changeset(attrs)
    |> Repo.insert()
  end

  # Generates a UUID4 idempotency_key and stores it in the options map
  # if one is not already present. This key survives Oban retries since
  # it is persisted on the ProcessingJob record at creation time.
  defp ensure_idempotency_key(attrs) do
    options = Map.get(attrs, :options) || Map.get(attrs, "options") || %{}

    if Map.has_key?(options, "idempotency_key") or Map.has_key?(options, :idempotency_key) do
      attrs
    else
      options = Map.put(options, "idempotency_key", Ecto.UUID.generate())

      attrs
      |> Map.put(:options, options)
      |> Map.delete("options")
    end
  end

  @doc """
  Updates a processing job.
  """
  @spec update_processing_job(ProcessingJob.t(), map()) ::
          {:ok, ProcessingJob.t()} | {:error, Ecto.Changeset.t()}
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
  @spec get_analysis_job!(String.t()) :: AnalysisJob.t()
  def get_analysis_job!(id), do: Repo.get!(AnalysisJob, id)

  @doc """
  Creates an analysis job.
  """
  @spec create_analysis_job(map()) :: {:ok, AnalysisJob.t()} | {:error, Ecto.Changeset.t()}
  def create_analysis_job(attrs \\ %{}) do
    %AnalysisJob{}
    |> AnalysisJob.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an analysis job.
  """
  @spec update_analysis_job(AnalysisJob.t(), map()) ::
          {:ok, AnalysisJob.t()} | {:error, Ecto.Changeset.t()}
  def update_analysis_job(%AnalysisJob{} = analysis_job, attrs) do
    analysis_job
    |> AnalysisJob.changeset(attrs)
    |> Repo.update()
  end

  # Stem functions

  @doc """
  Gets a single stem.
  """
  @spec get_stem!(String.t()) :: Stem.t()
  def get_stem!(id), do: Repo.get!(Stem, id)

  @doc """
  Lists all stems for a given track.
  """
  @spec list_stems_for_track(String.t()) :: [Stem.t()]
  def list_stems_for_track(track_id) do
    Stem
    |> where([s], s.track_id == ^track_id)
    |> Repo.all()
  end

  @doc """
  Creates a stem.
  """
  @spec create_stem(map()) :: {:ok, Stem.t()} | {:error, Ecto.Changeset.t()}
  def create_stem(attrs \\ %{}) do
    %Stem{}
    |> Stem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a stem from a DAW export. Uses `export_changeset/2` which does not
  require a `processing_job_id` since edited stems are user-generated.
  """
  @spec create_exported_stem(map()) :: {:ok, Stem.t()} | {:error, Ecto.Changeset.t()}
  def create_exported_stem(attrs) do
    %Stem{}
    |> Stem.export_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes all stems for a given track. Used for idempotent re-processing.
  """
  @spec delete_stems_for_track(String.t()) :: {non_neg_integer(), nil}
  def delete_stems_for_track(track_id) do
    Stem
    |> where([s], s.track_id == ^track_id)
    |> Repo.delete_all()
  end

  @doc """
  Deletes all analysis results for a given track. Used for idempotent re-analysis.
  """
  @spec delete_analysis_for_track(String.t()) :: {non_neg_integer(), nil}
  def delete_analysis_for_track(track_id) do
    AnalysisResult
    |> where([ar], ar.track_id == ^track_id)
    |> Repo.delete_all()
  end

  # AnalysisResult functions

  @doc """
  Gets the analysis result for a given track.
  """
  @spec get_analysis_result_for_track(String.t()) :: AnalysisResult.t() | nil
  def get_analysis_result_for_track(track_id) do
    AnalysisResult
    |> where([ar], ar.track_id == ^track_id)
    |> Repo.one()
  end

  @doc """
  Creates an analysis result.
  """
  @spec create_analysis_result(map()) :: {:ok, AnalysisResult.t()} | {:error, Ecto.Changeset.t()}
  def create_analysis_result(attrs \\ %{}) do
    %AnalysisResult{}
    |> AnalysisResult.changeset(attrs)
    |> Repo.insert()
  end
end
