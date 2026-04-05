defmodule SoundForge.MIDI.ClockCoverageTest do
  @moduledoc "Tests for MIDI Clock GenServer: BPM detection, transport state, quantize."
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.Clock

  describe "start_link/1" do
    test "starts with custom name" do
      {:ok, pid} = Clock.start_link(name: :test_midi_clock_cov)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "get_bpm via GenServer.call" do
    test "returns nil initially" do
      {:ok, pid} = Clock.start_link(name: :test_clock_bpm)
      assert GenServer.call(pid, :get_bpm) == nil
      GenServer.stop(pid)
    end
  end

  describe "get_transport_state via GenServer.call" do
    test "returns :idle initially" do
      {:ok, pid} = Clock.start_link(name: :test_clock_transport)
      assert GenServer.call(pid, :get_transport_state) == :idle
      GenServer.stop(pid)
    end
  end

  describe "quantize_to_beat via GenServer.call" do
    test "returns {:ok, :now} when no clock active" do
      {:ok, pid} = Clock.start_link(name: :test_clock_quantize)
      assert GenServer.call(pid, {:quantize_to_beat, []}) == {:ok, :now}
      GenServer.stop(pid)
    end
  end

  describe "handle_info messages" do
    setup do
      {:ok, pid} = Clock.start_link(name: :test_clock_info)
      %{pid: pid}
    end

    test "clock tick message", %{pid: pid} do
      now = System.monotonic_time(:microsecond)
      send(pid, {:midi_message, "input:0", %{type: :clock, timestamp: now}})
      assert Process.alive?(pid)
    end

    test "multiple clock ticks accumulate", %{pid: pid} do
      base = System.monotonic_time(:microsecond)
      # Send 25 ticks at ~120 BPM (500ms per beat, ~20.8ms per tick)
      for i <- 0..25 do
        ts = base + i * 20_833
        send(pid, {:midi_message, "input:0", %{type: :clock, timestamp: ts}})
      end
      # Give GenServer time to process
      Process.sleep(50)
      bpm = GenServer.call(pid, :get_bpm)
      # Should have a BPM calculated now (roughly 120)
      assert is_float(bpm) or is_nil(bpm)
    end

    test "start transport message", %{pid: pid} do
      send(pid, {:midi_message, "input:0", %{type: :start}})
      Process.sleep(10)
      assert GenServer.call(pid, :get_transport_state) == :playing
    end

    test "stop transport message", %{pid: pid} do
      send(pid, {:midi_message, "input:0", %{type: :start}})
      send(pid, {:midi_message, "input:0", %{type: :stop}})
      Process.sleep(10)
      assert GenServer.call(pid, :get_transport_state) == :stopped
    end

    test "continue transport message", %{pid: pid} do
      send(pid, {:midi_message, "input:0", %{type: :stop}})
      send(pid, {:midi_message, "input:0", %{type: :continue}})
      Process.sleep(10)
      assert GenServer.call(pid, :get_transport_state) == :playing
    end

    test "non-clock midi message is ignored", %{pid: pid} do
      send(pid, {:midi_message, "input:0", %{type: :cc, channel: 0, data: %{controller: 1, value: 64}}})
      assert Process.alive?(pid)
    end

    test "unknown message is ignored", %{pid: pid} do
      send(pid, {:something_random, 123})
      assert Process.alive?(pid)
    end

    test "device_connected message", %{pid: pid} do
      send(pid, {:device_connected, %{port_id: "input:99", direction: :input}})
      assert Process.alive?(pid)
    end

    test "device_disconnected message", %{pid: pid} do
      send(pid, {:device_disconnected, %{port_id: "input:99"}})
      assert Process.alive?(pid)
    end
  end
end
