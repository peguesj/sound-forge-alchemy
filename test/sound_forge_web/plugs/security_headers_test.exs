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

  test "CSP restricts object-src to none", %{conn: conn} do
    conn = get(conn, ~p"/")
    headers = Enum.into(conn.resp_headers, %{})
    assert headers["content-security-policy"] =~ "object-src 'none'"
  end

  test "CSP allows Spotify image CDN", %{conn: conn} do
    conn = get(conn, ~p"/")
    headers = Enum.into(conn.resp_headers, %{})
    assert headers["content-security-policy"] =~ "https://i.scdn.co"
  end

  test "CSP allows WebSocket connections", %{conn: conn} do
    conn = get(conn, ~p"/")
    headers = Enum.into(conn.resp_headers, %{})
    assert headers["content-security-policy"] =~ "connect-src 'self' ws: wss:"
  end

  test "CSP restricts base-uri to self", %{conn: conn} do
    conn = get(conn, ~p"/")
    headers = Enum.into(conn.resp_headers, %{})
    assert headers["content-security-policy"] =~ "base-uri 'self'"
  end

  test "permissions policy restricts sensitive APIs", %{conn: conn} do
    conn = get(conn, ~p"/")
    headers = Enum.into(conn.resp_headers, %{})
    assert headers["permissions-policy"] =~ "microphone=()"
    assert headers["permissions-policy"] =~ "geolocation=()"
  end
end
