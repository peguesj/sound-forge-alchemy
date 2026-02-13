defmodule SoundForgeWeb.UserSocket do
  @moduledoc """
  WebSocket connection handler for real-time channel communication.
  """
  use Phoenix.Socket

  channel "jobs:*", SoundForgeWeb.JobChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
