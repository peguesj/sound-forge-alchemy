defmodule SoundForge.OSC.ServerTest do
  use ExUnit.Case

  alias SoundForge.OSC.Server

  describe "start_link/1" do
    test "starts server on a random port" do
      port = Enum.random(40000..49999)
      assert {:ok, pid} = Server.start_link(port: port, name: :"osc_test_#{port}")
      assert is_pid(pid)
      assert Server.get_port(:"osc_test_#{port}") == port
      GenServer.stop(pid)
    end
  end

  describe "get_port/1" do
    test "returns the configured port" do
      port = Enum.random(40000..49999)
      {:ok, pid} = Server.start_link(port: port, name: :"osc_port_test_#{port}")
      assert Server.get_port(:"osc_port_test_#{port}") == port
      GenServer.stop(pid)
    end
  end

  describe "handle_info UDP" do
    test "broadcasts received OSC messages via PubSub" do
      port = Enum.random(40000..49999)
      {:ok, pid} = Server.start_link(port: port, name: :"osc_udp_test_#{port}")

      Phoenix.PubSub.subscribe(SoundForge.PubSub, "osc:messages")

      # Send a valid OSC message
      data = SoundForge.OSC.Parser.encode("/test", [42])
      {:ok, sender} = :gen_udp.open(0, [:binary])
      :gen_udp.send(sender, ~c"127.0.0.1", port, data)
      :gen_udp.close(sender)

      # Should receive the broadcast
      assert_receive {:osc_message, %{address: "/test"}, _sender}, 1000

      GenServer.stop(pid)
    end

    test "handles invalid OSC data gracefully" do
      port = Enum.random(40000..49999)
      {:ok, pid} = Server.start_link(port: port, name: :"osc_invalid_test_#{port}")

      {:ok, sender} = :gen_udp.open(0, [:binary])
      :gen_udp.send(sender, ~c"127.0.0.1", port, <<0, 0, 0>>)
      :gen_udp.close(sender)

      # Give it time to process - should not crash
      Process.sleep(100)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "handles unknown messages" do
      port = Enum.random(40000..49999)
      {:ok, pid} = Server.start_link(port: port, name: :"osc_unknown_test_#{port}")

      send(pid, :random_message)
      Process.sleep(50)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "terminate/2" do
    test "closes socket on termination" do
      port = Enum.random(40000..49999)
      {:ok, pid} = Server.start_link(port: port, name: :"osc_term_test_#{port}")
      # Normal stop triggers terminate callback
      GenServer.stop(pid, :normal)
      refute Process.alive?(pid)
    end

    test "handles nil socket in terminate" do
      assert :ok = Server.terminate(:normal, %{socket: nil, port: 0})
    end
  end
end
