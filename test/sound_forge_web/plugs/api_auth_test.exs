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
  end
end
