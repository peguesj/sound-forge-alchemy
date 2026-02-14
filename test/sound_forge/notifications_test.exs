defmodule SoundForge.NotificationsTest do
  use ExUnit.Case, async: false

  alias SoundForge.Notifications

  # The Notifications GenServer is started by the application supervision tree,
  # so ETS tables already exist. We use unique user IDs per test for isolation.

  describe "push/2" do
    test "stores a notification and returns :ok" do
      user_id = "user_#{System.unique_integer([:positive])}"
      assert :ok = Notifications.push(user_id, %{type: :success, title: "Done", message: "OK"})
    end

    test "broadcasts to PubSub topic" do
      user_id = "user_#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "notifications:#{user_id}")

      Notifications.push(user_id, %{type: :info, title: "Test", message: "Hello"})

      assert_receive {:new_notification, notification}
      assert notification.type == :info
      assert notification.title == "Test"
      assert notification.message == "Hello"
    end

    test "defaults type to :info" do
      user_id = "user_#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "notifications:#{user_id}")

      Notifications.push(user_id, %{title: "No type", message: "body"})

      assert_receive {:new_notification, notification}
      assert notification.type == :info
    end

    test "includes metadata" do
      user_id = "user_#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "notifications:#{user_id}")

      Notifications.push(user_id, %{
        type: :success,
        title: "Track",
        message: "Done",
        metadata: %{track_id: "abc-123"}
      })

      assert_receive {:new_notification, notification}
      assert notification.metadata == %{track_id: "abc-123"}
    end

    test "notification has an id and inserted_at" do
      user_id = "user_#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "notifications:#{user_id}")

      Notifications.push(user_id, %{title: "Test", message: "msg"})

      assert_receive {:new_notification, notification}
      assert is_binary(notification.id)
      assert %DateTime{} = notification.inserted_at
    end
  end

  describe "list/2" do
    test "returns empty list when no notifications exist" do
      user_id = "user_#{System.unique_integer([:positive])}"
      assert [] = Notifications.list(user_id)
    end

    test "returns notifications newest first" do
      user_id = "user_#{System.unique_integer([:positive])}"

      Notifications.push(user_id, %{title: "First", message: "1"})
      Process.sleep(1)
      Notifications.push(user_id, %{title: "Second", message: "2"})

      notifications = Notifications.list(user_id)
      assert length(notifications) == 2
      assert hd(notifications).title == "Second"
    end

    test "respects limit parameter" do
      user_id = "user_#{System.unique_integer([:positive])}"

      for i <- 1..5 do
        Notifications.push(user_id, %{title: "N#{i}", message: "msg"})
        Process.sleep(1)
      end

      assert length(Notifications.list(user_id, 3)) == 3
    end

    test "isolates notifications between users" do
      user_a = "user_a_#{System.unique_integer([:positive])}"
      user_b = "user_b_#{System.unique_integer([:positive])}"

      Notifications.push(user_a, %{title: "For A", message: "msg"})
      Notifications.push(user_b, %{title: "For B", message: "msg"})

      assert length(Notifications.list(user_a)) == 1
      assert hd(Notifications.list(user_a)).title == "For A"
    end
  end

  describe "mark_read/1" do
    test "marks all notifications as read" do
      user_id = "user_#{System.unique_integer([:positive])}"

      Notifications.push(user_id, %{title: "Unread", message: "msg"})
      Process.sleep(10)
      Notifications.mark_read(user_id)
      Process.sleep(10)

      notifications = Notifications.list(user_id)
      assert Enum.all?(notifications, & &1.read)
    end

    test "returns :ok" do
      user_id = "user_#{System.unique_integer([:positive])}"
      assert :ok = Notifications.mark_read(user_id)
    end
  end

  describe "unread_count/1" do
    test "returns 0 when no notifications exist" do
      user_id = "user_#{System.unique_integer([:positive])}"
      assert 0 = Notifications.unread_count(user_id)
    end

    test "counts unread notifications" do
      user_id = "user_#{System.unique_integer([:positive])}"

      Notifications.push(user_id, %{title: "One", message: "msg"})
      Notifications.push(user_id, %{title: "Two", message: "msg"})

      assert Notifications.unread_count(user_id) == 2
    end

    test "decreases after mark_read" do
      user_id = "user_#{System.unique_integer([:positive])}"

      Notifications.push(user_id, %{title: "One", message: "msg"})
      Process.sleep(10)
      Notifications.mark_read(user_id)
      Process.sleep(10)

      assert Notifications.unread_count(user_id) == 0
    end

    test "new notifications after mark_read are unread" do
      user_id = "user_#{System.unique_integer([:positive])}"

      Notifications.push(user_id, %{title: "Old", message: "msg"})
      Process.sleep(10)
      Notifications.mark_read(user_id)
      Process.sleep(10)
      Notifications.push(user_id, %{title: "New", message: "msg"})

      assert Notifications.unread_count(user_id) == 1
    end
  end

  describe "subscribe/1" do
    test "subscribes to PubSub topic for user" do
      user_id = "user_#{System.unique_integer([:positive])}"
      assert :ok = Notifications.subscribe(user_id)

      Notifications.push(user_id, %{title: "After sub", message: "msg"})
      assert_receive {:new_notification, _}
    end
  end
end
