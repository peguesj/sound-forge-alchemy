defmodule SoundForgeWeb.DjLive do
  @moduledoc """
  DJ LiveView -- redirects to dashboard DJ tab.

  The standalone DJ view is deprecated. All DJ functionality now lives in
  `SoundForgeWeb.Live.Components.DjTabComponent`. This module is retained
  for backwards-compatible URL redirects (/dj -> /?tab=dj).
  """
  use SoundForgeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/?#{[tab: "dj"]}")}
  end

  @impl true
  def render(assigns), do: ~H""
end
