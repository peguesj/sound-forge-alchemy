defmodule SoundForgeWeb.API.LalalaiControllerTest do
  use SoundForgeWeb.ConnCase

  import SoundForge.AccountsFixtures

  setup do
    user = user_fixture()
    conn = build_conn() |> log_in_user(user)
    %{conn: conn, user: user}
  end

  describe "GET /api/lalalai/quota" do
    test "returns quota information for authenticated user", %{conn: conn} do
      conn = get(conn, "/api/lalalai/quota")

      response = json_response(conn, conn.status)

      # Either returns quota (global key configured) or service_unavailable
      case conn.status do
        200 -> assert is_number(response["minutes_left"])
        503 -> assert response["error"] =~ "API key not configured"
      end
    end
  end

  describe "POST /api/lalalai/cancel" do
    test "returns 400 when task_id is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/lalalai/cancel", %{})

      assert json_response(conn, 400)["error"] =~ "task_id parameter is required"
    end

    test "returns 400 when task_id is empty string", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/lalalai/cancel", %{"task_id" => ""})

      assert json_response(conn, 400)["error"] =~ "task_id parameter is required"
    end
  end

  describe "POST /api/lalalai/cancel-all" do
    test "attempts cancellation for authenticated user", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/lalalai/cancel-all", %{})

      response = json_response(conn, conn.status)

      # May succeed (200), return service_unavailable (503), or bad_gateway (502)
      assert conn.status in [200, 502, 503]
      assert is_map(response)
    end
  end

  describe "authentication" do
    test "GET /api/lalalai/quota redirects unauthenticated users" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> fetch_flash()
        |> get("/api/lalalai/quota")

      assert redirected_to(conn) == "/users/log-in"
    end

    test "POST /api/lalalai/cancel redirects unauthenticated users" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_req_header("content-type", "application/json")
        |> post("/api/lalalai/cancel", %{"task_id" => "abc"})

      assert redirected_to(conn) == "/users/log-in"
    end
  end
end
