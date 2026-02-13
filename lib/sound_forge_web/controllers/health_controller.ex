defmodule SoundForgeWeb.HealthController do
  use SoundForgeWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok", version: "3.0.0"})
  end
end
