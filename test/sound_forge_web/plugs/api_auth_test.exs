defmodule SoundForgeWeb.Plugs.APIAuthTest do
  use SoundForgeWeb.ConnCase

  alias SoundForgeWeb.Plugs.APIAuth

  describe "call/2" do
    test "authenticates with valid Bearer token", %{conn: conn} do
      user = SoundForge.AccountsFixtures.user_fixture()
      token = SoundForge.Accounts.generate_user_session_token(user)
      encoded = Base.url_encode64(token, padding: false)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{encoded}")
        |> APIAuth.call([])

      assert conn.assigns[:current_user].id == user.id
      assert conn.assigns[:current_scope].user.id == user.id
      refute conn.halted
    end

    test "returns 401 for unauthenticated API request" do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{url: "https://open.spotify.com/track/123"})

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end

    test "returns 401 with invalid Bearer token" do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer invalidtoken")
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{url: "https://open.spotify.com/track/123"})

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end

    @tag :slow
    test "returns 401 when token TTL is expired" do
      user = SoundForge.AccountsFixtures.user_fixture()
      token = SoundForge.Accounts.generate_user_session_token(user)
      encoded = Base.url_encode64(token, padding: false)

      # Set TTL to 0 days and wait so age > 0 seconds
      Application.put_env(:sound_forge, :api_token_ttl_days, 0)
      Process.sleep(1100)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{encoded}")
        |> APIAuth.call([])

      assert conn.halted
      assert conn.status == 401

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Unauthorized"

      # Restore default
      Application.put_env(:sound_forge, :api_token_ttl_days, 30)
    end

    test "returns 401 with missing Bearer prefix" do
      conn =
        build_conn()
        |> put_req_header("authorization", "Token abc123")
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{url: "https://open.spotify.com/track/123"})

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end

    test "returns 401 with empty authorization header" do
      conn =
        build_conn()
        |> put_req_header("authorization", "")
        |> put_req_header("content-type", "application/json")
        |> post("/api/spotify/fetch", %{url: "https://open.spotify.com/track/123"})

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end
  end
end
