defmodule SoundForgeWeb.HealthControllerTest do
  use SoundForgeWeb.ConnCase

  describe "GET /health" do
    test "returns health check with version and checks", %{conn: conn} do
      conn = get(conn, ~p"/health")
      body = json_response(conn, conn.status)
      assert body["version"] == "3.0.0"
      assert body["status"] in ["ok", "degraded"]
      assert is_map(body["checks"])
      assert body["checks"]["database"]["status"] == "ok"
      assert body["checks"]["storage"]["status"] == "ok"
      assert is_map(body["checks"]["storage_stats"])
      assert body["checks"]["storage_stats"]["status"] == "ok"
      assert is_integer(body["checks"]["storage_stats"]["file_count"])
      assert is_number(body["checks"]["storage_stats"]["total_size_mb"])
      assert is_integer(body["uptime_seconds"])
    end

    test "includes oban check", %{conn: conn} do
      conn = get(conn, ~p"/health")
      body = json_response(conn, conn.status)
      assert is_map(body["checks"]["oban"])
      assert body["checks"]["oban"]["status"] in ["ok", "error"]
    end

    test "includes uptime_seconds as non-negative integer", %{conn: conn} do
      conn = get(conn, ~p"/health")
      body = json_response(conn, conn.status)
      assert body["uptime_seconds"] >= 0
    end

    test "returns consistent status based on checks", %{conn: conn} do
      conn = get(conn, ~p"/health")
      body = json_response(conn, conn.status)

      all_ok =
        body["checks"]
        |> Map.values()
        |> Enum.all?(fn check -> check["status"] == "ok" end)

      if all_ok do
        assert body["status"] == "ok"
        assert conn.status == 200
      else
        assert body["status"] == "degraded"
        assert conn.status == 503
      end
    end

    test "storage_stats includes file_count and total_size_mb", %{conn: conn} do
      conn = get(conn, ~p"/health")
      body = json_response(conn, conn.status)
      stats = body["checks"]["storage_stats"]

      assert stats["file_count"] >= 0
      assert stats["total_size_mb"] >= 0.0
    end
  end
end
