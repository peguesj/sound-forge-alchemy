defmodule SoundForge.Chat.BridgeTest do
  use ExUnit.Case, async: true

  alias SoundForge.Chat.Bridge

  setup do
    pubsub_name = :"chat_test_pubsub_#{System.unique_integer([:positive])}"
    start_supervised!({Phoenix.PubSub, name: pubsub_name})

    bridge =
      start_supervised!({
        Bridge,
        # Negative staleness makes every participant immediately stale, so the
        # eviction test is deterministic without Process.sleep.
        name: :"chat_bridge_#{System.unique_integer([:positive])}",
        pubsub: pubsub_name,
        max_messages: 3,
        stale_after_ms: -1,
        sweep_interval_ms: 0
      })

    Phoenix.PubSub.subscribe(pubsub_name, Bridge.topic())

    %{bridge: bridge}
  end

  test "join/leave broadcast presence", %{bridge: bridge} do
    assert {:ok, [%{sender: "alice"}]} = Bridge.join(bridge, "alice", %{"role" => "dev"})
    assert_receive {:chat_presence, [%{sender: "alice"}]}

    assert {:ok, []} = Bridge.leave(bridge, "alice")
    assert_receive {:chat_presence, []}
  end

  test "heartbeat implicitly joins and refreshes last_seen", %{bridge: bridge} do
    assert {:ok, [%{sender: "bob"}]} = Bridge.heartbeat(bridge, "bob")
    assert_receive {:chat_presence, [%{sender: "bob"}]}
  end

  test "stale participants are evicted on sweep", %{bridge: bridge} do
    Bridge.join(bridge, "carol")
    assert_receive {:chat_presence, _}

    send(bridge, :sweep)

    assert_receive {:chat_presence, []}
    assert Bridge.presence(bridge) == []
  end

  test "post_message stores and broadcasts", %{bridge: bridge} do
    assert {:ok, message} =
             Bridge.post_message(bridge, %{
               "sender" => "alice",
               "body" => "hi",
               "meta" => %{"x" => 1}
             })

    assert message.sender == "alice"
    assert message.body == "hi"
    assert_receive {:chat_message, ^message}
    assert [^message] = Bridge.messages(bridge)
  end

  test "message ring buffer caps at max_messages", %{bridge: bridge} do
    for i <- 1..5 do
      Bridge.post_message(bridge, %{"sender" => "a", "body" => "m#{i}"})
    end

    bodies = bridge |> Bridge.messages() |> Enum.map(& &1.body)
    assert bodies == ["m5", "m4", "m3"]
  end

  test "rejects invalid messages", %{bridge: bridge} do
    assert {:error, :invalid_message} = Bridge.post_message(bridge, %{"sender" => "a"})
    assert {:error, :invalid_message} = Bridge.post_message(bridge, %{"body" => "x"})
  end
end
