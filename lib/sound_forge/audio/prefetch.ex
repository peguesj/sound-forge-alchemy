defmodule SoundForge.Audio.Prefetch do
  @moduledoc """
  ETS-backed audio prefetch cache for DJ and DAW modes.

  Preloads track metadata (BPM, key, duration, stem info) into an ETS table
  when users enter DJ or DAW tabs so that track loading is near-instant.
  Uses `Task.async_stream` for parallel I/O when gathering file metadata.

  ## Cache Structure

  DJ mode caches analysis metadata per track:

      {:track_prefetch, track_id} => %{
        mode: :dj,
        track_id: track_id,
        title: "...",
        artist: "...",
        duration: 240,
        tempo: 128.0,
        key: "Cm",
        energy: 0.85,
        beat_times: [...],
        structure: %{...},
        loop_points: [...],
        bar_times: [...],
        arrangement_markers: [...],
        stem_count: 4,
        has_stems: true,
        cached_at: ~U[...]
      }

  DAW mode caches stem file metadata per track:

      {:track_prefetch, track_id} => %{
        mode: :daw,
        track_id: track_id,
        title: "...",
        artist: "...",
        stems: [
          %{id: "...", stem_type: :vocals, file_path: "...", file_size: 12345, exists: true},
          ...
        ],
        structure_segments: [...],
        bar_times: [...],
        cached_at: ~U[...]
      }

  Entries expire after a configurable TTL (default 10 minutes).
  """
  use GenServer

  import Ecto.Query, warn: false

  alias SoundForge.Music
  alias SoundForge.Music.{Track, Stem, AnalysisResult}
  alias SoundForge.Repo
  alias SoundForge.Storage
  alias SoundForge.Audio.AnalysisHelpers

  require Logger

  @table :sfa_track_prefetch
  @ttl_ms :timer.minutes(10)

  # ── Public API ──────────────────────────────────────────────────────

  @doc """
  Starts the Prefetch GenServer that owns the ETS table.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Asynchronously prefetches audio metadata for all eligible tracks
  belonging to the given user, optimized for DJ mode (BPM, key, beats, structure).

  Returns `:ok` immediately; prefetching happens in a background task.
  """
  @spec prefetch_for_dj(integer() | binary()) :: :ok
  def prefetch_for_dj(user_id) when not is_nil(user_id) do
    Task.Supervisor.start_child(SoundForge.TaskSupervisor, fn ->
      do_prefetch_dj(user_id)
    end)

    :ok
  end

  def prefetch_for_dj(_), do: :ok

  @doc """
  Asynchronously prefetches stem file metadata for all eligible tracks
  belonging to the given user, optimized for DAW mode (stem paths, sizes, existence).

  Returns `:ok` immediately; prefetching happens in a background task.
  """
  @spec prefetch_for_daw(integer() | binary()) :: :ok
  def prefetch_for_daw(user_id) when not is_nil(user_id) do
    Task.Supervisor.start_child(SoundForge.TaskSupervisor, fn ->
      do_prefetch_daw(user_id)
    end)

    :ok
  end

  def prefetch_for_daw(_), do: :ok

  @doc """
  Retrieves cached prefetch data for a track. Returns `nil` on cache miss
  or if the entry has expired past the TTL.
  """
  @spec get_cached(binary()) :: map() | nil
  def get_cached(track_id) when is_binary(track_id) do
    if table_exists?() do
      case :ets.lookup(@table, {:track_prefetch, track_id}) do
        [{{:track_prefetch, ^track_id}, entry}] ->
          if expired?(entry), do: nil, else: entry

        [] ->
          nil
      end
    else
      nil
    end
  end

  def get_cached(_), do: nil

  @doc """
  Retrieves cached prefetch data for a track, filtered to a specific mode.
  Returns `nil` if no cache entry exists, entry is expired, or mode doesn't match.
  """
  @spec get_cached(binary(), :dj | :daw) :: map() | nil
  def get_cached(track_id, mode) when is_binary(track_id) and mode in [:dj, :daw] do
    case get_cached(track_id) do
      %{mode: ^mode} = entry -> entry
      _ -> nil
    end
  end

  def get_cached(_, _), do: nil

  @doc """
  Manually inserts or updates a cache entry for a track.
  Useful for warming the cache after a track finishes processing.
  """
  @spec put_cached(binary(), map()) :: :ok
  def put_cached(track_id, data) when is_binary(track_id) and is_map(data) do
    if table_exists?() do
      entry = Map.put(data, :cached_at, DateTime.utc_now())
      :ets.insert(@table, {{:track_prefetch, track_id}, entry})
    end

    :ok
  end

  @doc """
  Invalidates the cache entry for a specific track.
  Call this when a track's stems or analysis data changes.
  """
  @spec invalidate(binary()) :: :ok
  def invalidate(track_id) when is_binary(track_id) do
    if table_exists?() do
      :ets.delete(@table, {:track_prefetch, track_id})
    end

    :ok
  end

  @doc """
  Returns the number of entries currently in the cache.
  """
  @spec cache_size() :: non_neg_integer()
  def cache_size do
    if table_exists?(), do: :ets.info(@table, :size), else: 0
  end

  @doc """
  Evicts all expired entries from the cache.
  Called periodically by the GenServer.
  """
  @spec evict_expired() :: non_neg_integer()
  def evict_expired do
    if table_exists?() do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -@ttl_ms, :millisecond)

      # Select keys where cached_at is before cutoff
      @table
      |> :ets.tab2list()
      |> Enum.count(fn {key, entry} ->
        if Map.get(entry, :cached_at) && DateTime.compare(entry.cached_at, cutoff) == :lt do
          :ets.delete(@table, key)
          true
        else
          false
        end
      end)
    else
      0
    end
  end

  # ── GenServer Callbacks ─────────────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    # Schedule periodic eviction every 5 minutes
    schedule_eviction()

    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:evict_expired, state) do
    count = evict_expired()

    if count > 0 do
      Logger.debug("[Prefetch] Evicted #{count} expired cache entries")
    end

    schedule_eviction()
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Private Implementation ──────────────────────────────────────────

  defp schedule_eviction do
    Process.send_after(self(), :evict_expired, :timer.minutes(5))
  end

  defp table_exists? do
    :ets.whereis(@table) != :undefined
  end

  defp expired?(%{cached_at: cached_at}) do
    diff = DateTime.diff(DateTime.utc_now(), cached_at, :millisecond)
    diff > @ttl_ms
  end

  defp expired?(_), do: true

  # ── DJ Prefetch ─────────────────────────────────────────────────────

  defp do_prefetch_dj(user_id) do
    tracks = eligible_tracks(user_id)
    Logger.debug("[Prefetch] DJ prefetch starting for #{length(tracks)} tracks (user #{user_id})")

    tracks
    |> Task.async_stream(&build_dj_cache_entry/1, max_concurrency: 4, timeout: 10_000)
    |> Enum.each(fn
      {:ok, {track_id, entry}} ->
        put_cached(track_id, entry)

      {:exit, reason} ->
        Logger.warning("[Prefetch] DJ prefetch task failed: #{inspect(reason)}")
    end)

    Logger.debug("[Prefetch] DJ prefetch complete, cache size: #{cache_size()}")
  end

  defp build_dj_cache_entry(track) do
    analysis = get_analysis(track.id)
    features = if analysis, do: analysis.features || %{}, else: %{}
    stem_count = Repo.aggregate(from(s in Stem, where: s.track_id == ^track.id), :count)

    entry = %{
      mode: :dj,
      track_id: track.id,
      title: track.title,
      artist: track.artist,
      duration: track.duration,
      tempo: if(analysis, do: analysis.tempo),
      key: if(analysis, do: analysis.key),
      energy: if(analysis, do: analysis.energy),
      beat_times: Map.get(features, "beats", []),
      structure: Map.get(features, "structure", %{}),
      loop_points: get_in(features, ["loop_points", "recommended"]) || [],
      bar_times: get_in(features, ["structure", "bar_times"]) || [],
      arrangement_markers: Map.get(features, "arrangement_markers", []),
      stem_count: stem_count,
      has_stems: stem_count > 0,
      cached_at: DateTime.utc_now()
    }

    {track.id, entry}
  end

  # ── DAW Prefetch ────────────────────────────────────────────────────

  defp do_prefetch_daw(user_id) do
    tracks = eligible_tracks(user_id)
    Logger.debug("[Prefetch] DAW prefetch starting for #{length(tracks)} tracks (user #{user_id})")

    tracks
    |> Task.async_stream(&build_daw_cache_entry/1, max_concurrency: 4, timeout: 10_000)
    |> Enum.each(fn
      {:ok, {track_id, entry}} ->
        put_cached(track_id, entry)

      {:exit, reason} ->
        Logger.warning("[Prefetch] DAW prefetch task failed: #{inspect(reason)}")
    end)

    Logger.debug("[Prefetch] DAW prefetch complete, cache size: #{cache_size()}")
  end

  defp build_daw_cache_entry(track) do
    stems = Music.list_stems_for_track(track.id)
    analysis = get_analysis(track.id)

    # Check file existence and gather sizes in parallel
    stem_metadata =
      stems
      |> Task.async_stream(
        fn stem ->
          full_path = resolve_stem_path(stem.file_path)
          exists = File.exists?(full_path)

          file_size =
            if exists do
              case File.stat(full_path) do
                {:ok, %{size: size}} -> size
                _ -> stem.file_size
              end
            else
              stem.file_size
            end

          %{
            id: stem.id,
            stem_type: stem.stem_type,
            file_path: stem.file_path,
            file_size: file_size,
            exists: exists,
            source: stem.source
          }
        end,
        max_concurrency: 8,
        timeout: 5_000
      )
      |> Enum.reduce([], fn
        {:ok, meta}, acc -> [meta | acc]
        {:exit, _reason}, acc -> acc
      end)
      |> Enum.reverse()

    {structure_segments, bar_times} =
      if analysis do
        {AnalysisHelpers.structure_segments(analysis), AnalysisHelpers.bar_times(analysis)}
      else
        {[], []}
      end

    entry = %{
      mode: :daw,
      track_id: track.id,
      title: track.title,
      artist: track.artist,
      stems: stem_metadata,
      structure_segments: structure_segments,
      bar_times: bar_times,
      cached_at: DateTime.utc_now()
    }

    {track.id, entry}
  end

  # ── Shared Helpers ──────────────────────────────────────────────────

  defp eligible_tracks(user_id) do
    # Tracks that are downloaded AND have at least one stem
    Track
    |> where([t], t.user_id == ^user_id)
    |> where(
      [t],
      fragment(
        "EXISTS (SELECT 1 FROM download_jobs WHERE download_jobs.track_id = ? AND download_jobs.status = 'completed')",
        t.id
      )
    )
    |> where(
      [t],
      fragment("EXISTS (SELECT 1 FROM stems WHERE stems.track_id = ?)", t.id)
    )
    |> Repo.all()
  end

  defp get_analysis(track_id) do
    AnalysisResult
    |> where([ar], ar.track_id == ^track_id)
    |> limit(1)
    |> Repo.one()
  end

  defp resolve_stem_path(nil), do: ""

  defp resolve_stem_path(path) do
    if String.starts_with?(path, "/") do
      path
    else
      Path.join([File.cwd!(), Storage.base_path(), path])
    end
  end
end
