defmodule SoundForgeWeb.UserSocketTest do
  use SoundForgeWeb.ChannelCase

  alias SoundForgeWeb.UserSocket

  describe "connect/3" do
    test "connects successfully with no params" do
      assert {:ok, _socket} = connect(UserSocket, %{})
    end

    test "connects successfully with arbitrary params" do
      assert {:ok, _socket} = connect(UserSocket, %{"token" => "abc"})
    end
  end

  describe "id/1" do
    test "returns nil for anonymous connections" do
      {:ok, socket} = connect(UserSocket, %{})
      assert UserSocket.id(socket) == nil
    end
  end

  describe "channel routing" do
    test "routes jobs:* to JobChannel" do
      {:ok, socket} = connect(UserSocket, %{})

      {:ok, _, _socket} =
        subscribe_and_join(socket, SoundForgeWeb.JobChannel, "jobs:test-123")
    end

    test "rejects unknown channel topics" do
      {:ok, socket} = connect(UserSocket, %{})

      assert_raise RuntimeError, ~r/no channel found/, fn ->
        subscribe_and_join(socket, "unknown:topic")
      end
    end
  end
end
