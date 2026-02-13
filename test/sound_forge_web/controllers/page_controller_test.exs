defmodule SoundForgeWeb.RootRedirectTest do
  use SoundForgeWeb.ConnCase

  setup :register_and_log_in_user

  test "GET / shows dashboard for authenticated users", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Sound Forge Alchemy"
  end

  test "GET / redirects unauthenticated users to login" do
    conn = build_conn()
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/users/log-in"
  end
end
