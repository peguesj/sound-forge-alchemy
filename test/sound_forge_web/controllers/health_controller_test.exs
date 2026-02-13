defmodule SoundForgeWeb.HealthControllerTest do
  use SoundForgeWeb.ConnCase

  describe "GET /health" do
    test "returns health check status", %{conn: conn} do
      conn = get(conn, ~p"/health")
      assert json_response(conn, 200) == %{"status" => "ok", "version" => "3.0.0"}
    end
  end
end
