defmodule SoundForge.OSC.ClientTest do
  use ExUnit.Case, async: true

  alias SoundForge.OSC.Client

  describe "send/4" do
    test "sends to localhost without error" do
      # Opens a listener, sends a message, verifies delivery
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      result = Client.send("127.0.0.1", port, "/test", [1.0])
      assert result == :ok

      # Verify data arrived
      assert {:ok, {_, _, data}} = :gen_udp.recv(socket, 0, 1000)
      assert is_binary(data)

      :gen_udp.close(socket)
    end

    test "sends with no args" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      assert :ok = Client.send("127.0.0.1", port, "/ping")

      :gen_udp.close(socket)
    end

    test "sends with multiple arg types" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      assert :ok = Client.send("127.0.0.1", port, "/multi", [42, 3.14, "hello"])

      :gen_udp.close(socket)
    end
  end
end
