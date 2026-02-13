defmodule SoundForgeWeb.HealthController do
  use SoundForgeWeb, :controller

  @version "3.0.0"

  def index(conn, _params) do
    checks = %{
      database: check_database(),
      oban: check_oban(),
      storage: check_storage(),
      storage_stats: storage_stats()
    }

    all_ok = Enum.all?(checks, fn {_k, v} -> v.status == "ok" end)
    status = if all_ok, do: "ok", else: "degraded"
    http_status = if all_ok, do: 200, else: 503

    conn
    |> put_status(http_status)
    |> json(%{
      status: status,
      version: @version,
      uptime_seconds: uptime_seconds(),
      checks: checks
    })
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(SoundForge.Repo, "SELECT 1", []) do
      {:ok, _} -> %{status: "ok"}
      {:error, reason} -> %{status: "error", message: inspect(reason)}
    end
  rescue
    e -> %{status: "error", message: Exception.message(e)}
  end

  defp check_oban do
    if Process.whereis(Oban.Registry) do
      %{status: "ok"}
    else
      %{status: "error", message: "Oban not running"}
    end
  end

  defp check_storage do
    base = SoundForge.Storage.base_path()

    if File.dir?(base) do
      case System.cmd("df", ["-k", base], stderr_to_stdout: true) do
        {output, 0} ->
          lines = String.split(output, "\n", trim: true)

          case lines do
            [_header, data | _] ->
              parts = String.split(data, ~r/\s+/)
              available_kb = Enum.at(parts, 3, "0") |> String.to_integer()
              available_mb = div(available_kb, 1024)
              %{status: "ok", available_mb: available_mb}

            _ ->
              %{status: "ok", path: base}
          end

        _ ->
          %{status: "ok", path: base}
      end
    else
      %{status: "error", message: "Storage directory missing: #{base}"}
    end
  end

  defp storage_stats do
    stats = SoundForge.Storage.stats()
    %{status: "ok", file_count: stats.file_count, total_size_mb: stats.total_size_mb}
  rescue
    e -> %{status: "error", message: Exception.message(e)}
  end

  defp uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end
end
