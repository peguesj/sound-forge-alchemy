defmodule SoundForge.MIDI.Clock do
  @moduledoc """
  GenServer that tracks incoming MIDI clock messages (24 ppqn) to derive BPM.

  Subscribes to `SoundForge.MIDI.Dispatcher` messages from all input devices
  and filters for clock/transport system messages. Calculates BPM from tick
  intervals using a rolling average over 24 ticks (one beat), and broadcasts
  smoothed BPM updates and transport state changes on the `"midi:clock"` topic.

  ## PubSub Messages

    * `{:bpm_update, float()}` - Smoothed BPM value (rolling average of 24 ticks)
    * `{:transport, :start | :stop | :continue}` - MIDI transport state changes

  ## Public API

    * `get_bpm/0` - Returns the current detected BPM or `nil`
    * `get_transport_state/0` - Returns `:playing`, `:stopped`, or `:idle`
    * `quantize_to_beat/1` - Returns timing info to snap to the next beat boundary
  """

  use GenServer

  require Logger

  alias SoundForge.MIDI.{DeviceManager, Dispatcher}

  @pubsub SoundForge.PubSub
  @topic "midi:clock"
  @ticks_per_beat 24
  @microseconds_per_minute 60_000_000

  # -- Types --

  @type transport_state :: :playing | :stopped | :idle

  # -- Public API --

  @doc """
  Starts the MIDI Clock GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the current detected BPM, or `nil` if no clock source is present.
  """
  @spec get_bpm() :: float() | nil
  def get_bpm do
    GenServer.call(__MODULE__, :get_bpm)
  end

  @doc """
  Returns the current transport state: `:playing`, `:stopped`, or `:idle`.
  """
  @spec get_transport_state() :: transport_state()
  def get_transport_state do
    GenServer.call(__MODULE__, :get_transport_state)
  end

  @doc """
  Determines whether a stem action should execute immediately or wait for
  the next beat boundary.

  Returns `{:ok, :now}` when no clock is active or the action falls on a
  beat boundary. Returns `{:ok, :wait, ms}` with milliseconds until the
  next beat boundary when clock is active and a beat is in progress.
  """
  @spec quantize_to_beat(keyword()) :: {:ok, :now} | {:ok, :wait, non_neg_integer()}
  def quantize_to_beat(opts \\ []) do
    GenServer.call(__MODULE__, {:quantize_to_beat, opts})
  end

  @doc """
  Subscribes the calling process to clock updates on the `"midi:clock"` topic.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  # -- Callbacks --

  @impl true
  def init(_opts) do
    DeviceManager.subscribe()
    subscribed_ports = subscribe_to_existing_devices()

    state = %{
      tick_timestamps: :queue.new(),
      tick_count: 0,
      bpm: nil,
      transport_state: :idle,
      last_tick_at: nil,
      last_beat_at: nil,
      subscribed_ports: subscribed_ports
    }

    Logger.info("MIDI Clock started, subscribed to #{MapSet.size(subscribed_ports)} input port(s)")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_bpm, _from, state) do
    {:reply, state.bpm, state}
  end

  def handle_call(:get_transport_state, _from, state) do
    {:reply, state.transport_state, state}
  end

  def handle_call({:quantize_to_beat, _opts}, _from, state) do
    result = calculate_quantize(state)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:midi_message, _port_id, %{type: :clock} = msg}, state) do
    now = msg.timestamp
    state = handle_clock_tick(state, now)
    {:noreply, state}
  end

  def handle_info({:midi_message, _port_id, %{type: :start}}, state) do
    Logger.info("MIDI Clock: received Start")
    state = %{state | transport_state: :playing, tick_count: 0, last_beat_at: monotonic_us()}
    broadcast_transport(:start)
    {:noreply, state}
  end

  def handle_info({:midi_message, _port_id, %{type: :stop}}, state) do
    Logger.info("MIDI Clock: received Stop")
    state = %{state | transport_state: :stopped}
    broadcast_transport(:stop)
    {:noreply, state}
  end

  def handle_info({:midi_message, _port_id, %{type: :continue}}, state) do
    Logger.info("MIDI Clock: received Continue")
    state = %{state | transport_state: :playing}
    broadcast_transport(:continue)
    {:noreply, state}
  end

  def handle_info({:midi_message, _port_id, _msg}, state) do
    {:noreply, state}
  end

  def handle_info({:device_connected, device}, state) do
    port_id = device.port_id

    if MapSet.member?(state.subscribed_ports, port_id) do
      {:noreply, state}
    else
      Dispatcher.subscribe(port_id)
      Logger.info("MIDI Clock: subscribed to new device port #{port_id}")
      {:noreply, %{state | subscribed_ports: MapSet.put(state.subscribed_ports, port_id)}}
    end
  end

  def handle_info({:device_disconnected, device}, state) do
    {:noreply, %{state | subscribed_ports: MapSet.delete(state.subscribed_ports, device.port_id)}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -- Private --

  defp handle_clock_tick(state, now) do
    tick_timestamps = :queue.in(now, state.tick_timestamps)
    tick_count = state.tick_count + 1
    queue_len = :queue.len(tick_timestamps)

    {tick_timestamps, bpm} =
      cond do
        queue_len > @ticks_per_beat ->
          {{:value, oldest}, trimmed} = :queue.out(tick_timestamps)
          interval_us = now - oldest
          calculated_bpm = @microseconds_per_minute / (interval_us / @ticks_per_beat)
          {trimmed, calculated_bpm}

        queue_len == @ticks_per_beat ->
          {{:value, oldest}, _rest} = :queue.out(tick_timestamps)
          interval_us = now - oldest
          calculated_bpm = @microseconds_per_minute / (interval_us / (@ticks_per_beat - 1))
          {tick_timestamps, calculated_bpm}

        true ->
          {tick_timestamps, state.bpm}
      end

    last_beat_at =
      if rem(tick_count, @ticks_per_beat) == 0 do
        now
      else
        state.last_beat_at
      end

    new_state = %{
      state
      | tick_timestamps: tick_timestamps,
        tick_count: tick_count,
        bpm: bpm,
        last_tick_at: now,
        last_beat_at: last_beat_at
    }

    if bpm != nil and rem(tick_count, @ticks_per_beat) == 0 do
      broadcast_bpm(bpm)
    end

    new_state
  end

  defp calculate_quantize(%{bpm: nil}), do: {:ok, :now}
  defp calculate_quantize(%{transport_state: :stopped}), do: {:ok, :now}
  defp calculate_quantize(%{transport_state: :idle}), do: {:ok, :now}
  defp calculate_quantize(%{last_beat_at: nil}), do: {:ok, :now}

  defp calculate_quantize(state) do
    now = monotonic_us()
    beat_duration_us = trunc(@microseconds_per_minute / state.bpm)
    elapsed_since_beat = now - state.last_beat_at
    remaining_us = beat_duration_us - rem(elapsed_since_beat, beat_duration_us)

    threshold = trunc(beat_duration_us * 0.05)

    if remaining_us <= threshold or remaining_us >= beat_duration_us - threshold do
      {:ok, :now}
    else
      ms = trunc(remaining_us / 1000)
      {:ok, :wait, max(ms, 1)}
    end
  end

  defp subscribe_to_existing_devices do
    DeviceManager.list_devices()
    |> Enum.filter(fn device -> device[:direction] == :input end)
    |> Enum.reduce(MapSet.new(), fn device, acc ->
      Dispatcher.subscribe(device.port_id)
      MapSet.put(acc, device.port_id)
    end)
  end

  defp broadcast_bpm(bpm) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:bpm_update, Float.round(bpm, 1)})
  end

  defp broadcast_transport(event) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:transport, event})
  end

  defp monotonic_us do
    System.monotonic_time(:microsecond)
  end
end
