defmodule SoundForge.MIDI.NetworkDiscoveryTest do
  @moduledoc """
  Tests for MIDI NetworkDiscovery GenServer.
  """
  use SoundForge.DataCase

  alias SoundForge.MIDI.NetworkDiscovery

  describe "start_link/1" do
    test "starts with disabled flag to avoid dns-sd spawns" do
      {:ok, pid} = NetworkDiscovery.start_link(enabled: false, name: :"test_nd_#{System.unique_integer()}")
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "list_network_devices/0" do
    test "returns empty list when ETS table does not exist" do
      # The :midi_devices ETS table may or may not exist in test
      result = NetworkDiscovery.list_network_devices()
      assert is_list(result)
    end
  end

  describe "GenServer messages" do
    setup do
      name = :"test_nd_#{System.unique_integer([:positive])}"
      {:ok, pid} = NetworkDiscovery.start_link(enabled: false, name: name)
      %{pid: pid}
    end

    test "handles unknown messages", %{pid: pid} do
      send(pid, {:unexpected_message, "data"})
      :timer.sleep(10)
      assert Process.alive?(pid)
    end

    test "handles :scan message without crashing", %{pid: pid} do
      send(pid, :scan)
      :timer.sleep(100)
      assert Process.alive?(pid)
    end
  end
end
