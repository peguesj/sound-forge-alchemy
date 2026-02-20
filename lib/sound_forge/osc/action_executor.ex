defmodule SoundForge.OSC.ActionExecutor do
  @moduledoc """
  Maps incoming OSC addresses to SFA actions and sends feedback.
  """
  use GenServer
  require Logger

  @touchosc_host "192.168.1.255"
  @touchosc_port 9000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    Phoenix.PubSub.subscribe(SoundForge.PubSub, "osc:messages")
    Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_playback")

    state = %{
      touchosc_host: Keyword.get(opts, :touchosc_host, @touchosc_host),
      touchosc_port: Keyword.get(opts, :touchosc_port, @touchosc_port),
      stem_volumes: %{},
      stem_mutes: %{},
      stem_solos: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:osc_message, %{address: address, args: args}, _sender}, state) do
    state = route_osc(address, args, state)
    {:noreply, state}
  end

  def handle_info({:stem_volume_changed, stem, value}, state) do
    send_feedback(state, "/stem/#{stem}/volume", [value / 1.0])
    {:noreply, put_in_nested(state, [:stem_volumes, stem], value)}
  end

  def handle_info({:playback_state, action}, state) do
    case action do
      :playing -> send_feedback(state, "/transport/play", [1.0])
      :stopped -> send_feedback(state, "/transport/play", [0.0])
      _ -> :ok
    end
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- OSC Address Routing --

  defp route_osc("/transport/play", _args, state) do
    Phoenix.PubSub.broadcast(SoundForge.PubSub, "track_playback", {:action, :play})
    state
  end

  defp route_osc("/transport/stop", _args, state) do
    Phoenix.PubSub.broadcast(SoundForge.PubSub, "track_playback", {:action, :stop})
    state
  end

  defp route_osc("/transport/next", _args, state) do
    Phoenix.PubSub.broadcast(SoundForge.PubSub, "track_playback", {:action, :next_track})
    state
  end

  defp route_osc("/transport/prev", _args, state) do
    Phoenix.PubSub.broadcast(SoundForge.PubSub, "track_playback", {:action, :prev_track})
    state
  end

  defp route_osc("/stem/" <> rest, args, state) do
    case String.split(rest, "/", parts: 2) do
      [n_str, "volume"] ->
        stem = parse_int(n_str)
        value = List.first(args) || 0.0
        Phoenix.PubSub.broadcast(SoundForge.PubSub, "track_playback", {:stem_volume, stem, value})
        put_in_nested(state, [:stem_volumes, stem], value)

      [n_str, "mute"] ->
        stem = parse_int(n_str)
        on = (List.first(args) || 0.0) >= 0.5
        Phoenix.PubSub.broadcast(SoundForge.PubSub, "track_playback", {:stem_mute, stem, on})
        put_in_nested(state, [:stem_mutes, stem], on)

      [n_str, "solo"] ->
        stem = parse_int(n_str)
        on = (List.first(args) || 0.0) >= 0.5
        Phoenix.PubSub.broadcast(SoundForge.PubSub, "track_playback", {:stem_solo, stem, on})
        put_in_nested(state, [:stem_solos, stem], on)

      _ ->
        Logger.debug("OSC ActionExecutor: unknown stem address /stem/#{rest}")
        state
    end
  end

  defp route_osc(address, _args, state) do
    Logger.debug("OSC ActionExecutor: no route for #{address}")
    state
  end

  defp send_feedback(state, address, args) do
    SoundForge.OSC.Client.send(state.touchosc_host, state.touchosc_port, address, args)
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp put_in_nested(state, [key1, key2], value) do
    Map.update(state, key1, %{key2 => value}, &Map.put(&1, key2, value))
  end
end
