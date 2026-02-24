defmodule SoundForgeWeb.DawLive do
  @moduledoc """
  DAW LiveView -- redirects to dashboard DAW tab.

  The standalone DAW view is deprecated. All DAW functionality now lives in
  `SoundForgeWeb.Live.Components.DawTabComponent`. This module is retained
  for backwards-compatible URL redirects (/daw/:track_id -> /?tab=daw&track_id=X).
  """
  use SoundForgeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"track_id" => track_id}, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/?#{[tab: "daw", track_id: track_id]}")}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/?#{[tab: "daw"]}")}
  end

  @impl true
  def render(assigns), do: ~H""
end
