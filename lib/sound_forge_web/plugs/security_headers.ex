defmodule SoundForgeWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Plug to set security-related HTTP headers.
  """
  import Plug.Conn

  @behaviour Plug

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    conn
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("x-xss-protection", "1; mode=block")
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("permissions-policy", "camera=(), microphone=(), geolocation=()")
    |> put_resp_header("content-security-policy", csp_value())
  end

  defp csp_value do
    frame_src =
      if Application.get_env(:sound_forge, :dev_routes),
        do: "frame-src 'self' https://sdk.scdn.co",
        else: "frame-src 'self' https://sdk.scdn.co"

    directives = [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' https://sdk.scdn.co",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: https://i.scdn.co https://*.scdn.co https://*.spotifycdn.com",
      "font-src 'self' data:",
      "connect-src 'self' ws: wss: https://api.spotify.com",
      "media-src 'self' blob:",
      frame_src,
      "object-src 'none'",
      "base-uri 'self'"
    ]

    Enum.join(directives, "; ")
  end
end
