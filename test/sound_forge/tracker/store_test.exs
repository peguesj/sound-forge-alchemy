defmodule SoundForge.Tracker.StoreTest do
  use ExUnit.Case, async: true

  alias SoundForge.Tracker.Store

  setup do
    pubsub_name = :"tracker_test_pubsub_#{System.unique_integer([:positive])}"
    start_supervised!({Phoenix.PubSub, name: pubsub_name})

    store =
      start_supervised!(
        {Store,
         name: :"tracker_store_#{System.unique_integer([:positive])}",
         pubsub: pubsub_name,
         max_cards: 5}
      )

    Phoenix.PubSub.subscribe(pubsub_name, Store.topic())

    %{store: store}
  end

  test "add_card/2 returns snapshot and broadcasts it", %{store: store} do
    assert {:ok, snapshot} = Store.add_card(store, %{"run" => "abc", "step" => 1})
    assert snapshot.online
    assert snapshot.card_count == 1
    assert [%{card: %{"run" => "abc", "step" => 1}}] = snapshot.cards

    assert_receive {:tracker_snapshot, ^snapshot}
  end

  test "rejects non-map cards", %{store: store} do
    assert {:error, :invalid_card} = Store.add_card(store, "nope")
  end

  test "ring buffer caps at max_cards", %{store: store} do
    for i <- 1..10, do: Store.add_card(store, %{"i" => i})

    snapshot = Store.snapshot(store)
    assert snapshot.card_count == 5
    assert snapshot.total_ingested == 10
    # Newest first
    assert Enum.map(snapshot.cards, & &1.card["i"]) == [10, 9, 8, 7, 6]
  end

  test "snapshot/1 reflects current state without mutation broadcast", %{store: store} do
    Store.add_card(store, %{"a" => 1})
    assert_receive {:tracker_snapshot, _}

    snapshot = Store.snapshot(store)
    assert snapshot.card_count == 1
    refute_receive {:tracker_snapshot, _}, 50
  end

  test "reset/1 clears cards and broadcasts", %{store: store} do
    Store.add_card(store, %{"a" => 1})
    assert_receive {:tracker_snapshot, _}

    assert :ok = Store.reset(store)
    assert_receive {:tracker_snapshot, %{card_count: 0}}
  end
end
