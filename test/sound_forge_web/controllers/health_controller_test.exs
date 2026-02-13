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
      assert is_integer(body["uptime_seconds"])
    end
  end
end
