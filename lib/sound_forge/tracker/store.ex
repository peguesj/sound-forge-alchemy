defmodule SoundForge.Tracker.Store do
  @moduledoc """
  In-memory realtime tracker store.

  Holds ingested "cards" (arbitrary JSON evidence snapshots with run
  identifiers) in a bounded ring buffer (max 500 cards, time-bounded).
  After every mutation a full state snapshot is broadcast as
  `{:tracker_snapshot, snapshot}` on the `"tracker:events"` PubSub topic.
  """

  use GenServer

  @topic "tracker:events"
  @max_cards 500
  # Cards older than this many seconds are evicted lazily on each mutation/read.
  @max_age_seconds 24 * 60 * 60

  ## Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "PubSub topic snapshots are broadcast on."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc """
  Ingest a card (map). Returns `{:ok, snapshot}`.
  """
  @spec add_card(GenServer.server(), map()) :: {:ok, map()} | {:error, :invalid_card}
  def add_card(server \\ __MODULE__, card)

  def add_card(server, card) when is_map(card) do
    GenServer.call(server, {:add_card, card})
  end

  def add_card(_server, _card), do: {:error, :invalid_card}

  @doc "Current full state snapshot."
  @spec snapshot(GenServer.server()) :: map()
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  end

  @doc "Clears all cards. Broadcasts a fresh snapshot."
  @spec reset(GenServer.server()) :: :ok
  def reset(server \\ __MODULE__) do
    GenServer.call(server, :reset)
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    state = %{
      cards: [],
      count: 0,
      started_at: DateTime.utc_now(),
      max_cards: Keyword.get(opts, :max_cards, @max_cards),
      max_age_seconds: Keyword.get(opts, :max_age_seconds, @max_age_seconds),
      pubsub: Keyword.get(opts, :pubsub, SoundForge.PubSub)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_card, card}, _from, state) do
    entry = %{
      id: Ecto.UUID.generate(),
      received_at: DateTime.utc_now(),
      card: card
    }

    cards =
      [entry | state.cards]
      |> prune(state)

    state = %{state | cards: cards, count: state.count + 1}
    snap = build_snapshot(state)
    broadcast(state, snap)
    {:reply, {:ok, snap}, state}
  end

  def handle_call(:snapshot, _from, state) do
    state = %{state | cards: prune(state.cards, state)}
    {:reply, build_snapshot(state), state}
  end

  def handle_call(:reset, _from, state) do
    state = %{state | cards: []}
    broadcast(state, build_snapshot(state))
    {:reply, :ok, state}
  end

  ## Internal

  defp prune(cards, state) do
    cutoff = DateTime.add(DateTime.utc_now(), -state.max_age_seconds, :second)

    cards
    |> Enum.take(state.max_cards)
    |> Enum.reject(fn %{received_at: at} -> DateTime.compare(at, cutoff) == :lt end)
  end

  defp build_snapshot(state) do
    %{
      online: true,
      started_at: state.started_at,
      total_ingested: state.count,
      card_count: length(state.cards),
      cards:
        Enum.map(state.cards, fn entry ->
          %{id: entry.id, received_at: entry.received_at, card: entry.card}
        end)
    }
  end

  defp broadcast(state, snap) do
    Phoenix.PubSub.broadcast(state.pubsub, @topic, {:tracker_snapshot, snap})
  end
end
