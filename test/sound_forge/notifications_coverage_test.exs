defmodule SoundForge.NotificationsCoverageTest do
  @moduledoc "Tests for Notifications ETS-backed store."
  use ExUnit.Case

  alias SoundForge.Notifications

  setup do
    # Ensure the GenServer is running so ETS tables exist.
    # It's started in application.ex, but in case it isn't:
    case GenServer.whereis(Notifications) do
      nil ->
        {:ok, _pid} =
          Notifications.start_link(
            name: :"notifications_test_#{System.unique_integer([:positive])}"
          )

        :ok

      _pid ->
        :ok
    end

    user_id = System.unique_integer([:positive])
    %{user_id: user_id}
  end

  describe "push/2" do
    test "pushes a notification", %{user_id: user_id} do
      assert :ok = Notifications.push(user_id, %{type: :info, title: "Test", message: "Hello"})
    end

    test "pushes with metadata", %{user_id: user_id} do
      assert :ok =
               Notifications.push(user_id, %{
                 type: :success,
                 title: "Done",
                 message: "Complete",
                 metadata: %{track_id: "abc"}
               })
    end
  end

  describe "list/2" do
    test "returns empty list for user with no notifications", %{user_id: user_id} do
      assert Notifications.list(user_id) == []
    end

    test "returns notifications after push", %{user_id: user_id} do
      Notifications.push(user_id, %{type: :info, title: "N1", message: "msg1"})
      :timer.sleep(10)
      Notifications.push(user_id, %{type: :warning, title: "N2", message: "msg2"})

      result = Notifications.list(user_id)
      assert length(result) == 2
      # Most recent first
      assert hd(result).title == "N2"
    end

    test "respects limit", %{user_id: user_id} do
      for i <- 1..5 do
        Notifications.push(user_id, %{type: :info, title: "N#{i}", message: "msg#{i}"})
        :timer.sleep(2)
      end

      result = Notifications.list(user_id, 3)
      assert length(result) == 3
    end
  end

  describe "mark_read/1" do
    test "marks all as read", %{user_id: user_id} do
      Notifications.push(user_id, %{type: :info, title: "Test", message: "msg"})
      assert :ok = Notifications.mark_read(user_id)
    end
  end

  describe "unread_count/1" do
    test "returns 0 for user with no notifications", %{user_id: user_id} do
      assert Notifications.unread_count(user_id) == 0
    end

    test "returns count of unread notifications", %{user_id: user_id} do
      Notifications.push(user_id, %{type: :info, title: "A", message: "msg"})
      Notifications.push(user_id, %{type: :info, title: "B", message: "msg"})
      assert Notifications.unread_count(user_id) == 2
    end

    test "returns 0 after marking read", %{user_id: user_id} do
      Notifications.push(user_id, %{type: :info, title: "A", message: "msg"})
      :timer.sleep(10)
      Notifications.mark_read(user_id)
      assert Notifications.unread_count(user_id) == 0
    end

    test "counts only new notifications after mark_read", %{user_id: user_id} do
      Notifications.push(user_id, %{type: :info, title: "Old", message: "old"})
      :timer.sleep(10)
      Notifications.mark_read(user_id)
      :timer.sleep(10)
      Notifications.push(user_id, %{type: :info, title: "New", message: "new"})
      assert Notifications.unread_count(user_id) == 1
    end
  end

  describe "subscribe/1" do
    test "subscribes to user notifications", %{user_id: user_id} do
      assert :ok = Notifications.subscribe(user_id)
    end
  end
end
