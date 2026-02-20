defmodule SoundForge.Integrations.Melodics do
  @moduledoc """
  Imports practice session data from the Melodics desktop application.

  Melodics stores practice data locally. This module reads that data
  and imports it into the SFA database for analysis and recommendations.
  """

  alias SoundForge.Repo
  alias SoundForge.Integrations.Melodics.MelodicsSession
  import Ecto.Query

  require Logger

  @data_dirs [
    Path.expand("~/.melodics"),
    Path.expand("~/Library/Application Support/Melodics"),
    Path.expand("~/Library/Application Support/com.melodics.Melodics")
  ]

  @doc "Import sessions from Melodics local data directory."
  @spec import_sessions(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def import_sessions(user_id) do
    case find_data_dir() do
      {:ok, dir} ->
        sessions = parse_sessions(dir)
        imported = insert_sessions(user_id, sessions)
        Logger.info("Melodics: imported #{imported} sessions for user #{user_id}")
        {:ok, imported}

      {:error, :not_found} ->
        Logger.info("Melodics data directory not found")
        {:error, :melodics_not_found}
    end
  end

  @doc "List all sessions for a user."
  @spec list_sessions(String.t(), keyword()) :: [MelodicsSession.t()]
  def list_sessions(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    MelodicsSession
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], desc: s.practiced_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Get practice stats for a user."
  @spec get_stats(String.t()) :: map()
  def get_stats(user_id) do
    sessions = list_sessions(user_id, limit: 100)

    %{
      total_sessions: length(sessions),
      avg_accuracy: avg_field(sessions, :accuracy),
      avg_bpm: avg_field(sessions, :bpm),
      instruments: sessions |> Enum.map(& &1.instrument) |> Enum.uniq() |> Enum.reject(&is_nil/1),
      sessions_this_week: count_this_week(sessions),
      bpm_trend: bpm_trend(sessions)
    }
  end

  @doc "Find the Melodics data directory."
  @spec find_data_dir() :: {:ok, String.t()} | {:error, :not_found}
  def find_data_dir do
    Enum.find_value(@data_dirs, {:error, :not_found}, fn dir ->
      if File.dir?(dir), do: {:ok, dir}
    end)
  end

  # -- Private --

  defp parse_sessions(dir) do
    json_files = Path.wildcard(Path.join(dir, "**/*.json"))

    json_files
    |> Enum.flat_map(&parse_session_file/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_session_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} when is_list(data) ->
            Enum.map(data, &normalize_session/1)
          {:ok, data} when is_map(data) ->
            [normalize_session(data)]
          _ -> []
        end
      _ -> []
    end
  end

  defp normalize_session(data) when is_map(data) do
    %{
      lesson_name: data["lesson_name"] || data["lessonName"] || data["name"],
      accuracy: parse_float(data["accuracy"] || data["score"]),
      bpm: parse_int(data["bpm"] || data["tempo"]),
      instrument: data["instrument"] || data["instrument_type"],
      practiced_at: parse_datetime(data["practiced_at"] || data["timestamp"] || data["date"])
    }
  end
  defp normalize_session(_), do: nil

  defp insert_sessions(user_id, sessions) do
    sessions
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(0, fn session_data, count ->
      attrs = Map.put(session_data, :user_id, user_id)
      changeset = MelodicsSession.changeset(%MelodicsSession{}, attrs)

      case Repo.insert(changeset) do
        {:ok, _} -> count + 1
        {:error, _} -> count
      end
    end)
  end

  defp avg_field([], _field), do: nil
  defp avg_field(sessions, field) do
    values = sessions |> Enum.map(&Map.get(&1, field)) |> Enum.reject(&is_nil/1)
    if values == [], do: nil, else: Enum.sum(values) / length(values)
  end

  defp count_this_week(sessions) do
    week_ago = DateTime.utc_now() |> DateTime.add(-7, :day)
    Enum.count(sessions, fn s ->
      s.practiced_at && DateTime.compare(s.practiced_at, week_ago) == :gt
    end)
  end

  defp bpm_trend(sessions) do
    sessions
    |> Enum.filter(& &1.bpm)
    |> Enum.take(10)
    |> Enum.map(& &1.bpm)
    |> Enum.reverse()
  end

  defp parse_float(nil), do: nil
  defp parse_float(v) when is_float(v), do: v
  defp parse_float(v) when is_integer(v), do: v / 1.0
  defp parse_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end
  defp parse_float(_), do: nil

  defp parse_int(nil), do: nil
  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_float(v), do: round(v)
  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> nil
    end
  end
  defp parse_int(_), do: nil

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
  defp parse_datetime(_), do: nil
end
