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

    test "returns 429 when limit is exceeded", %{conn: conn} do
      opts = RateLimiter.init(limit: 2, window_ms: 60_000)

      # Exhaust the limit
      _conn1 = RateLimiter.call(conn, opts)
      _conn2 = RateLimiter.call(build_conn(), opts)

      # Third request should be blocked
      conn3 = RateLimiter.call(build_conn(), opts)
      assert conn3.halted
      assert conn3.status == 429
      assert get_resp_header(conn3, "x-ratelimit-remaining") == ["0"]
      assert get_resp_header(conn3, "retry-after") == ["60"]

      body = Jason.decode!(conn3.resp_body)
      assert body["error"] == "Too Many Requests"
    end

    test "resets after window expires" do
      opts = RateLimiter.init(limit: 1, window_ms: 1)

      _conn1 = RateLimiter.call(build_conn(), opts)
      # Wait for the window to expire
      Process.sleep(5)

      conn2 = RateLimiter.call(build_conn(), opts)
      refute conn2.halted
    end

    test "uses X-Forwarded-For header when present" do
      opts = RateLimiter.init(limit: 1, window_ms: 60_000)

      # First request from IP "10.0.0.1"
      conn1 =
        build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-for", "10.0.0.1")
        |> RateLimiter.call(opts)

      refute conn1.halted

      # Second request from same forwarded IP should be blocked
      conn2 =
        build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-for", "10.0.0.1")
        |> RateLimiter.call(opts)

      assert conn2.halted
      assert conn2.status == 429
    end

    test "different X-Forwarded-For IPs have separate limits" do
      opts = RateLimiter.init(limit: 1, window_ms: 60_000)

      conn1 =
        build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-for", "10.0.0.1")
        |> RateLimiter.call(opts)

      refute conn1.halted

      # Different IP should still be allowed
      conn2 =
        build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-for", "10.0.0.2")
        |> RateLimiter.call(opts)

      refute conn2.halted
    end

    test "uses first IP from X-Forwarded-For chain" do
      opts = RateLimiter.init(limit: 1, window_ms: 60_000)

      # Multi-hop chain: client, proxy1, proxy2
      conn1 =
        build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-for", "10.0.0.1, 192.168.1.1, 172.16.0.1")
        |> RateLimiter.call(opts)

      refute conn1.halted

      # Same client IP in chain should be blocked
      conn2 =
        build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-for", "10.0.0.1, 192.168.1.2")
        |> RateLimiter.call(opts)

      assert conn2.halted
    end
  end
end
