defmodule SoundForge.Chat.Bridge do
  @moduledoc """
  In-memory chat bridge: presence map (join/leave/heartbeat with stale
  eviction) and a bounded message ring buffer.

  Broadcasts on the `"chat:events"` PubSub topic:

    * `{:chat_message, message}` when a message is posted
    * `{:chat_presence, presence_list}` when presence changes
  """

  use GenServer

  @topic "chat:events"
  @max_messages 200
  # Participants with no heartbeat for this many ms are evicted.
  @stale_after_ms 60_000
  @sweep_interval_ms 15_000

  ## Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "Join (or refresh) a participant. Broadcasts presence."
  @spec join(GenServer.server(), String.t(), map()) :: {:ok, [map()]}
  def join(server \\ __MODULE__, sender, meta \\ %{}) when is_binary(sender) do
    GenServer.call(server, {:join, sender, meta})
  end

  @doc "Leave. Broadcasts presence."
  @spec leave(GenServer.server(), String.t()) :: {:ok, [map()]}
  def leave(server \\ __MODULE__, sender) when is_binary(sender) do
    GenServer.call(server, {:leave, sender})
  end

  @doc "Heartbeat: refreshes last_seen (implicit join if unknown)."
  @spec heartbeat(GenServer.server(), String.t()) :: {:ok, [map()]}
  def heartbeat(server \\ __MODULE__, sender) when is_binary(sender) do
    GenServer.call(server, {:heartbeat, sender})
  end

  @doc "Post a chat message. Broadcasts `{:chat_message, message}`."
  @spec post_message(GenServer.server(), map()) :: {:ok, map()} | {:error, :invalid_message}
  def post_message(server \\ __MODULE__, attrs)

  def post_message(server, %{"sender" => sender, "body" => body} = attrs)
      when is_binary(sender) and is_binary(body) do
    GenServer.call(server, {:post_message, sender, body, Map.get(attrs, "meta", %{})})
  end

  def post_message(server, %{sender: sender, body: body} = attrs)
      when is_binary(sender) and is_binary(body) do
    GenServer.call(server, {:post_message, sender, body, Map.get(attrs, :meta, %{})})
  end

  def post_message(_server, _attrs), do: {:error, :invalid_message}

  @doc "Recent messages, newest first."
  @spec messages(GenServer.server()) :: [map()]
  def messages(server \\ __MODULE__), do: GenServer.call(server, :messages)

  @doc "Current presence list."
  @spec presence(GenServer.server()) :: [map()]
  def presence(server \\ __MODULE__), do: GenServer.call(server, :presence)

  ## Server callbacks

  @impl true
  def init(opts) do
    state = %{
      presence: %{},
      messages: [],
      max_messages: Keyword.get(opts, :max_messages, @max_messages),
      stale_after_ms: Keyword.get(opts, :stale_after_ms, @stale_after_ms),
      pubsub: Keyword.get(opts, :pubsub, SoundForge.PubSub)
    }

    sweep = Keyword.get(opts, :sweep_interval_ms, @sweep_interval_ms)
    if sweep > 0, do: :timer.send_interval(sweep, :sweep)

    {:ok, state}
  end

  @impl true
  def handle_call({:join, sender, meta}, _from, state) do
    entry = %{sender: sender, meta: meta, joined_at: now_ms(), last_seen: now_ms()}
    state = put_in(state.presence[sender], entry)
    {:reply, {:ok, broadcast_presence(state)}, state}
  end

  def handle_call({:leave, sender}, _from, state) do
    state = %{state | presence: Map.delete(state.presence, sender)}
    {:reply, {:ok, broadcast_presence(state)}, state}
  end

  def handle_call({:heartbeat, sender}, _from, state) do
    entry =
      case state.presence[sender] do
        nil -> %{sender: sender, meta: %{}, joined_at: now_ms(), last_seen: now_ms()}
        existing -> %{existing | last_seen: now_ms()}
      end

    state = put_in(state.presence[sender], entry)
    {:reply, {:ok, broadcast_presence(state)}, state}
  end

  def handle_call({:post_message, sender, body, meta}, _from, state) do
    message = %{
      id: Ecto.UUID.generate(),
      sender: sender,
      body: body,
      meta: meta,
      posted_at: DateTime.utc_now()
    }

    messages = Enum.take([message | state.messages], state.max_messages)
    state = %{state | messages: messages}
    Phoenix.PubSub.broadcast(state.pubsub, @topic, {:chat_message, message})
    {:reply, {:ok, message}, state}
  end

  def handle_call(:messages, _from, state), do: {:reply, state.messages, state}

  def handle_call(:presence, _from, state), do: {:reply, presence_list(state), state}

  @impl true
  def handle_info(:sweep, state) do
    cutoff = now_ms() - state.stale_after_ms
    {stale, fresh} = Map.split_with(state.presence, fn {_k, v} -> v.last_seen < cutoff end)
    state = %{state | presence: fresh}

    if map_size(stale) > 0, do: broadcast_presence(state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Internal

  defp now_ms, do: System.system_time(:millisecond)

  defp presence_list(state) do
    state.presence
    |> Map.values()
    |> Enum.sort_by(& &1.joined_at)
  end

  defp broadcast_presence(state) do
    list = presence_list(state)
    Phoenix.PubSub.broadcast(state.pubsub, @topic, {:chat_presence, list})
    list
  end
end
