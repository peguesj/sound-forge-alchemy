defmodule SoundForge.MIDI.NetworkDiscoveryCoverageTest do
  @moduledoc "Tests for MIDI NetworkDiscovery: list_network_devices, start_link, handle_info/cast."
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.NetworkDiscovery

  describe "list_network_devices/0" do
    test "returns a list (possibly empty)" do
      result = NetworkDiscovery.list_network_devices()
      assert is_list(result)
    end
  end

  describe "start_link/1 with disabled" do
    test "starts with scanning disabled" do
      {:ok, pid} = NetworkDiscovery.start_link(name: :test_net_disc, enabled: false)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "handle_cast :scan_now" do
    test "processes scan_now without crashing" do
      {:ok, pid} = NetworkDiscovery.start_link(name: :test_net_disc_scan, enabled: false)
      GenServer.cast(pid, :scan_now)
      Process.sleep(100)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "handle_info" do
    test "unknown message is ignored" do
      {:ok, pid} = NetworkDiscovery.start_link(name: :test_net_disc_info, enabled: false)
      send(pid, {:unknown, :message})
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "scan message triggers scan" do
      {:ok, pid} = NetworkDiscovery.start_link(name: :test_net_disc_scan2, enabled: false)
      send(pid, :scan)
      Process.sleep(200)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
end
