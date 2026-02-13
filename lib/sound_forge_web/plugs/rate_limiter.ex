defmodule SoundForgeWeb.Plugs.RateLimiter do
  @moduledoc """
  Simple ETS-based rate limiter for API endpoints.
  Limits requests per IP address within a sliding window.
  """
  import Plug.Conn

  @default_limit 60
  @default_window_ms 60_000

  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, @default_limit),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms)
    }
  end

  def call(conn, %{limit: limit, window_ms: window_ms}) do
    ensure_table()
    key = rate_limit_key(conn)
    now = System.monotonic_time(:millisecond)
    window_start = now - window_ms

    # Clean old entries and count current window
    clean_old_entries(key, window_start)
    count = count_entries(key)

    if count < limit do
      :ets.insert(:rate_limiter, {key, now})

      conn
      |> put_resp_header("x-ratelimit-limit", to_string(limit))
      |> put_resp_header("x-ratelimit-remaining", to_string(limit - count - 1))
    else
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("x-ratelimit-limit", to_string(limit))
      |> put_resp_header("x-ratelimit-remaining", "0")
      |> put_resp_header("retry-after", to_string(div(window_ms, 1000)))
      |> send_resp(429, Jason.encode!(%{error: "Too Many Requests", message: "Rate limit exceeded. Try again later."}))
      |> halt()
    end
  end

  defp ensure_table do
    case :ets.info(:rate_limiter) do
      :undefined ->
        try do
          :ets.new(:rate_limiter, [:bag, :public, :named_table])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end

  defp rate_limit_key(conn) do
    ip =
      conn.remote_ip
      |> :inet.ntoa()
      |> to_string()

    "rate:#{ip}"
  end

  defp clean_old_entries(key, window_start) do
    :ets.select_delete(:rate_limiter, [{{key, :"$1"}, [{:<, :"$1", window_start}], [true]}])
  end

  defp count_entries(key) do
    :ets.select_count(:rate_limiter, [{{key, :_}, [], [true]}])
  end
end
