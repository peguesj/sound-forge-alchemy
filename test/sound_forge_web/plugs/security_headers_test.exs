defmodule SoundForgeWeb.Plugs.SecurityHeadersTest do
  use SoundForgeWeb.ConnCase

  setup :register_and_log_in_user

  test "sets security headers on browser requests", %{conn: conn} do
    conn = get(conn, ~p"/")
    headers = Enum.into(conn.resp_headers, %{})

    assert headers["x-content-type-options"] == "nosniff"
    assert headers["x-frame-options"] == "DENY"
    assert headers["x-xss-protection"] == "1; mode=block"
    assert headers["referrer-policy"] == "strict-origin-when-cross-origin"
    assert headers["permissions-policy"] =~ "camera=()"
    assert headers["content-security-policy"] =~ "default-src 'self'"
    assert headers["content-security-policy"] =~ "img-src"
    refute headers["content-security-policy"] =~ "unsafe-eval"
  end
end
