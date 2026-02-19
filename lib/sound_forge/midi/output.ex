defmodule SoundForge.MIDI.Output do
  @moduledoc """
  GenServer that sends MIDI messages to output ports with rate limiting
  and connection pooling.

  Supports sending note_on, note_off, cc, program_change, and sysex messages.
  Accepts either a `%SoundForge.MIDI.Message{}` struct or a plain map with
  `:type`, `:channel`, and `:data` keys.

  ## Rate Limiting

  Uses a token bucket algorithm capped at 100 messages per 50ms window to
  prevent MIDI buffer overflow. Messages that exceed the rate limit are queued
  and drained on the next refill tick.

  ## Connection Pooling

  Output port connections are opened lazily on first send and cached by
  `port_id`. Connections are monitored and cleaned up on failure.

  ## PubSub Events

  Broadcasts on `"midi:output"`:
    - `{:midi_send_error, port_id, reason}` - when a send fails
  """

  use GenServer

  require Logger

  @max_tokens 100
  @refill_interval_ms 50

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the Output GenServer and links it to the calling process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Sends a MIDI message to the given `port_id`.

  Accepts either a `%SoundForge.MIDI.Message{}` struct or a map with
  `:type`, `:channel`, and `:data` keys.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec send(String.t(), struct() | map()) :: :ok | {:error, term()}
  def send(port_id, message) do
    GenServer.call(__MODULE__, {:send, port_id, message})
  end

  @doc """
  Sends raw sysex bytes to the given `port_id`.

  `data` is a list of integers (0-255) representing the sysex payload.
  The caller is responsible for including F0/F7 framing bytes if required
  by the target device.
  """
  @spec send_sysex(String.t(), [non_neg_integer()]) :: :ok | {:error, term()}
  def send_sysex(port_id, data) when is_list(data) do
    GenServer.call(__MODULE__, {:send, port_id, %{type: :sysex, channel: 0, data: data}})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    schedule_refill()

    state = %{
      connections: %{},
      tokens: @max_tokens,
      queue: :queue.new()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send, port_id, message}, _from, state) do
    normalized = normalize_message(message)

    case normalized do
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {:ok, msg} ->
        if state.tokens > 0 do
          {result, state} = do_send(port_id, msg, state)
          {:reply, result, %{state | tokens: state.tokens - 1}}
        else
          entry = {port_id, msg}
          {:reply, :ok, %{state | queue: :queue.in(entry, state.queue)}}
        end
    end
  end

  @impl true
  def handle_info(:refill_tokens, state) do
    schedule_refill()
    state = %{state | tokens: @max_tokens}
    state = drain_queue(state)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    connections =
      state.connections
      |> Enum.reject(fn {_port_id, {conn_pid, _ref}} -> conn_pid == pid end)
      |> Map.new()

    {:noreply, %{state | connections: connections}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp schedule_refill do
    Process.send_after(self(), :refill_tokens, @refill_interval_ms)
  end

  defp normalize_message(%{type: type, channel: channel, data: data})
       when type in [:note_on, :note_off, :cc, :program_change, :sysex] do
    {:ok, %{type: type, channel: channel, data: data}}
  end

  defp normalize_message(%{type: type}) do
    {:error, {:unsupported_message_type, type}}
  end

  defp normalize_message(_other) do
    {:error, :invalid_message_format}
  end

  defp do_send(port_id, msg, state) do
    {conn, state} = ensure_connection(port_id, state)

    case conn do
      nil ->
        broadcast_error(port_id, :connection_failed)
        {{:error, :connection_failed}, state}

      conn_ref ->
        case send_midi(conn_ref, msg) do
          :ok ->
            {:ok, state}

          {:error, reason} = err ->
            Logger.warning("MIDI output send failed on port #{port_id}: #{inspect(reason)}")
            broadcast_error(port_id, reason)
            {err, state}
        end
    end
  end

  defp ensure_connection(port_id, state) do
    case Map.get(state.connections, port_id) do
      {conn, _ref} ->
        {conn, state}

      nil ->
        case open_connection(port_id) do
          {:ok, conn} ->
            ref = Process.monitor(conn)
            connections = Map.put(state.connections, port_id, {conn, ref})
            {conn, %{state | connections: connections}}

          {:error, reason} ->
            Logger.error("Failed to open MIDI output port #{port_id}: #{inspect(reason)}")
            {nil, state}
        end
    end
  end

  defp open_connection(port_id) do
    try do
      case Midiex.open(port_id) do
        {:ok, conn} -> {:ok, conn}
        {:error, reason} -> {:error, reason}
        conn -> {:ok, conn}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp send_midi(conn, %{type: :sysex, data: data}) do
    try do
      Midiex.send_msg(conn, data)
      :ok
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp send_midi(conn, %{type: type, channel: channel, data: data}) do
    bytes = encode_message(type, channel, data)

    try do
      Midiex.send_msg(conn, bytes)
      :ok
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp encode_message(:note_on, channel, %{note: note, velocity: vel}) do
    [0x90 + channel, note, vel]
  end

  defp encode_message(:note_on, channel, [note, vel]) do
    [0x90 + channel, note, vel]
  end

  defp encode_message(:note_off, channel, %{note: note, velocity: vel}) do
    [0x80 + channel, note, vel]
  end

  defp encode_message(:note_off, channel, [note, vel]) do
    [0x80 + channel, note, vel]
  end

  defp encode_message(:cc, channel, %{controller: cc_num, value: val}) do
    [0xB0 + channel, cc_num, val]
  end

  defp encode_message(:cc, channel, [cc_num, val]) do
    [0xB0 + channel, cc_num, val]
  end

  defp encode_message(:program_change, channel, %{program: program}) do
    [0xC0 + channel, program]
  end

  defp encode_message(:program_change, channel, [program]) do
    [0xC0 + channel, program]
  end

  defp encode_message(:program_change, channel, program) when is_integer(program) do
    [0xC0 + channel, program]
  end

  defp drain_queue(state) do
    drain_queue(state, @max_tokens)
  end

  defp drain_queue(state, 0), do: state

  defp drain_queue(state, remaining) do
    case :queue.out(state.queue) do
      {:empty, _queue} ->
        %{state | tokens: remaining}

      {{:value, {port_id, msg}}, queue} ->
        {_result, state} = do_send(port_id, msg, %{state | queue: queue})
        drain_queue(state, remaining - 1)
    end
  end

  defp broadcast_error(port_id, reason) do
    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "midi:output",
      {:midi_send_error, port_id, reason}
    )
  end
end
