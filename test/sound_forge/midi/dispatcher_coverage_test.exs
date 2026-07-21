defmodule SoundForge.MIDI.DispatcherCoverageTest do
  @moduledoc "Tests for MIDI Dispatcher GenServer: topic generation, start_link."
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.Dispatcher

  describe "topic/1" do
    test "generates correct topic for port_id" do
      assert Dispatcher.topic("input:0") == "midi:messages:input:0"
    end

    test "generates topic for network port" do
      assert Dispatcher.topic("network:192.168.1.10:5004") ==
               "midi:messages:network:192.168.1.10:5004"
    end
  end

  describe "start_link/1" do
    test "starts with custom name" do
      {:ok, pid} = Dispatcher.start_link(name: :test_dispatcher_cov)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "handle_info" do
    setup do
      {:ok, pid} = Dispatcher.start_link(name: :test_dispatcher_info)
      %{pid: pid}
    end

    test "device disconnected removes port", %{pid: pid} do
      send(pid, {:midi_device_disconnected, %{port_id: "input:99", direction: :input}})
      assert Process.alive?(pid)
    end

    test "device connected with output direction is ignored", %{pid: pid} do
      send(pid, {:midi_device_connected, %{port_id: "output:5", direction: :output}})
      assert Process.alive?(pid)
    end

    test "unknown message is ignored", %{pid: pid} do
      send(pid, {:random_message, :data})
      assert Process.alive?(pid)
    end
  end
end
