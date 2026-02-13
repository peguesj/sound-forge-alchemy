defmodule SoundForgeWeb.AudioPlayerLive do
  use SoundForgeWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:playing, false)
     |> assign(:current_time, 0)
     |> assign(:duration, 0)
     |> assign(:volume, 80)
     |> assign(:muted_stems, MapSet.new())}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("toggle_play", _params, socket) do
    {:noreply, assign(socket, :playing, !socket.assigns.playing)}
  end

  @impl true
  def handle_event("seek", %{"time" => time}, socket) do
    {:noreply, assign(socket, :current_time, time)}
  end

  @impl true
  def handle_event("volume", %{"level" => level}, socket) do
    {:noreply, assign(socket, :volume, level)}
  end

  @impl true
  def handle_event("toggle_stem", %{"stem" => stem}, socket) do
    muted = socket.assigns.muted_stems

    muted =
      if MapSet.member?(muted, stem),
        do: MapSet.delete(muted, stem),
        else: MapSet.put(muted, stem)

    {:noreply, assign(socket, :muted_stems, muted)}
  end

  @impl true
  def handle_event("player_ready", %{"duration" => duration}, socket) do
    {:noreply, assign(socket, :duration, duration)}
  end

  @impl true
  def handle_event("time_update", %{"time" => time}, socket) do
    {:noreply, assign(socket, :current_time, time)}
  end

  defp format_time(seconds) when is_number(seconds) do
    minutes = trunc(seconds / 60)
    secs = trunc(rem(trunc(seconds), 60))

    "#{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(secs), 2, "0")}"
  end

  defp format_time(_), do: "00:00"
end
