defmodule SoundForgeWeb.PageControllerTest do
  use SoundForgeWeb.ConnCase

  setup :register_and_log_in_user

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Sound Forge Alchemy"
  end

  test "GET / redirects unauthenticated users" do
    conn = build_conn()
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/users/log-in"
  end
end
