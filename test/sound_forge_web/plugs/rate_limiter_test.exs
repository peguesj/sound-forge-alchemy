defmodule SoundForgeWeb.Plugs.RateLimiterTest do
  use SoundForgeWeb.ConnCase

  alias SoundForgeWeb.Plugs.RateLimiter

  setup do
    # Clean ETS table between tests
    case :ets.info(:rate_limiter) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(:rate_limiter)
    end

    :ok
  end

  describe "init/1" do
    test "uses defaults" do
      opts = RateLimiter.init([])
      assert opts.limit == 60
      assert opts.window_ms == 60_000
    end

    test "accepts custom values" do
      opts = RateLimiter.init(limit: 10, window_ms: 30_000)
      assert opts.limit == 10
      assert opts.window_ms == 30_000
    end
  end

  describe "call/2" do
    test "allows requests under the limit", %{conn: conn} do
      opts = RateLimiter.init(limit: 5, window_ms: 60_000)
      conn = RateLimiter.call(conn, opts)

      refute conn.halted
      assert get_resp_header(conn, "x-ratelimit-limit") == ["5"]
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["4"]
    end

    test "decrements remaining count", %{conn: conn} do
      opts = RateLimiter.init(limit: 5, window_ms: 60_000)

      conn1 = RateLimiter.call(conn, opts)
      assert get_resp_header(conn1, "x-ratelimit-remaining") == ["4"]

      conn2 = RateLimiter.call(build_conn(), opts)
      assert get_resp_header(conn2, "x-ratelimit-remaining") == ["3"]
    end

    test "includes rate limit headers", %{conn: conn} do
      opts = RateLimiter.init(limit: 10, window_ms: 60_000)
      conn = RateLimiter.call(conn, opts)

      assert get_resp_header(conn, "x-ratelimit-limit") == ["10"]
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["9"]
    end
  end
end
