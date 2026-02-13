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
  end
end
