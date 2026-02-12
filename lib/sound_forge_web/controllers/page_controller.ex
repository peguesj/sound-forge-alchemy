defmodule SoundForgeWeb.PageController do
  use SoundForgeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
