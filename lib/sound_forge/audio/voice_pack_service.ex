defmodule SoundForge.Audio.VoicePackService do
  @moduledoc """
  Service module for managing voice pack metadata with time-based caching.

  Checks the `voice_packs` table first. If the cached data is older than 1 hour,
  refreshes from the lalal.ai API via `LalalAI.list_voice_packs/0` and upserts
  the results. Always includes the 7 builtin voice packs.
  """

  import Ecto.Query

  alias SoundForge.Audio.LalalAI
  alias SoundForge.Audio.VoicePack
  alias SoundForge.Repo

  require Logger

  @cache_ttl_seconds 3600

  @builtin_packs [
    "ALEX_KAYE",
    "STASIA_FAYE",
    "NICOLAAS_HAAS",
    "NIK_ZEL",
    "OLIA_CHEBO",
    "YVAR_DE_GROOT",
    "VETRANA"
  ]

  @doc """
  Returns the list of 7 builtin voice pack names.
  """
  @spec builtin_packs() :: [String.t()]
  def builtin_packs, do: @builtin_packs

  @doc """
  Lists voice packs, using the database as a time-based cache.

  1. Queries the `voice_packs` table for the most recent `cached_at` timestamp.
  2. If data exists and is less than 1 hour old, returns the cached rows.
  3. Otherwise, calls `LalalAI.list_voice_packs/0` to refresh the cache
     and returns the freshly upserted rows.

  Returns `{:ok, [%VoicePack{}]}` on success, or `{:error, reason}` on failure.
  """
  @spec list_packs() :: {:ok, [VoicePack.t()]} | {:error, term()}
  def list_packs do
    case cached_packs() do
      {:fresh, packs} ->
        {:ok, packs}

      :stale ->
        case refresh_cache() do
          {:ok, packs} -> {:ok, packs}
          {:error, reason} -> fallback_or_error(reason)
        end
    end
  end

  @doc """
  Forces a refresh of the voice pack cache from the lalal.ai API.

  Calls `LalalAI.list_voice_packs/0`, upserts results into the `voice_packs`
  table, and returns the updated list.

  Returns `{:ok, [%VoicePack{}]}` on success, or `{:error, reason}` on failure.
  """
  @spec refresh_cache() :: {:ok, [VoicePack.t()]} | {:error, term()}
  def refresh_cache do
    case LalalAI.list_voice_packs() do
      {:ok, packs_data} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        upsert_packs(packs_data, now)

      {:error, reason} ->
        Logger.warning("Failed to refresh voice packs from lalal.ai: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Queries the cache and determines freshness.
  @spec cached_packs() :: {:fresh, [VoicePack.t()]} | :stale
  defp cached_packs do
    packs =
      VoicePack
      |> order_by([vp], asc: vp.name)
      |> Repo.all()

    case packs do
      [] ->
        :stale

      packs ->
        newest_cached_at =
          packs
          |> Enum.map(& &1.cached_at)
          |> Enum.reject(&is_nil/1)
          |> Enum.max(DateTime, fn -> nil end)

        if fresh?(newest_cached_at) do
          {:fresh, packs}
        else
          :stale
        end
    end
  end

  # Returns true if the given timestamp is within the cache TTL window.
  @spec fresh?(DateTime.t() | nil) :: boolean()
  defp fresh?(nil), do: false

  defp fresh?(%DateTime{} = cached_at) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, cached_at, :second)
    diff < @cache_ttl_seconds
  end

  # Upserts a list of voice pack maps from the API into the database.
  # Each map is expected to have "id" (pack_id), "name", and optionally "created_at".
  @spec upsert_packs([map()], DateTime.t()) :: {:ok, [VoicePack.t()]}
  defp upsert_packs(packs_data, now) do
    Enum.each(packs_data, fn pack_map ->
      pack_id = to_string(pack_map["id"] || pack_map[:id] || "")
      name = to_string(pack_map["name"] || pack_map[:name] || pack_id)

      created_at_remote =
        case pack_map["created_at"] || pack_map[:created_at] do
          nil -> nil
          ts when is_binary(ts) -> parse_datetime(ts)
          %DateTime{} = dt -> DateTime.truncate(dt, :second)
          _ -> nil
        end

      attrs = %{
        pack_id: pack_id,
        name: name,
        created_at_remote: created_at_remote,
        cached_at: now
      }

      Repo.insert!(
        VoicePack.changeset(%VoicePack{}, attrs),
        on_conflict: {:replace, [:name, :created_at_remote, :cached_at, :updated_at]},
        conflict_target: :pack_id
      )
    end)

    packs =
      VoicePack
      |> order_by([vp], asc: vp.name)
      |> Repo.all()

    {:ok, packs}
  end

  # If the API call fails but we have stale data, return stale data as a fallback.
  # If no data exists at all, propagate the error.
  @spec fallback_or_error(term()) :: {:ok, [VoicePack.t()]} | {:error, term()}
  defp fallback_or_error(reason) do
    packs =
      VoicePack
      |> order_by([vp], asc: vp.name)
      |> Repo.all()

    case packs do
      [] ->
        {:error, reason}

      stale_packs ->
        Logger.info("Returning stale voice pack cache (#{length(stale_packs)} packs)")
        {:ok, stale_packs}
    end
  end

  # Attempts to parse an ISO 8601 datetime string.
  @spec parse_datetime(String.t()) :: DateTime.t() | nil
  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end
