defmodule SoundForge.MIDI.ClockTest do
  @moduledoc "Tests for MIDI.Clock GenServer API."
  use ExUnit.Case

  alias SoundForge.MIDI.Clock

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Clock)
    end

    test "start_link/1 is exported" do
      assert {:start_link, 1} in Clock.__info__(:functions)
    end

    test "get_bpm/0 is exported" do
      assert {:get_bpm, 0} in Clock.__info__(:functions)
    end

    test "get_transport_state/0 is exported" do
      assert {:get_transport_state, 0} in Clock.__info__(:functions)
    end

    test "quantize_to_beat/0 is exported" do
      assert {:quantize_to_beat, 0} in Clock.__info__(:functions)
    end

    test "quantize_to_beat/1 is exported" do
      assert {:quantize_to_beat, 1} in Clock.__info__(:functions)
    end

    test "subscribe/0 is exported" do
      assert {:subscribe, 0} in Clock.__info__(:functions)
    end
  end

  describe "GenServer lifecycle" do
    setup do
      name = :"clock_test_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Clock.start_link(name: name)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{pid: pid, name: name}
    end

    test "starts and runs", %{pid: pid} do
      assert Process.alive?(pid)
    end

    test "get_bpm returns nil initially", %{pid: pid} do
      result = GenServer.call(pid, :get_bpm)
      assert is_nil(result)
    end

    test "get_transport_state returns :idle initially", %{pid: pid} do
      state = GenServer.call(pid, :get_transport_state)
      assert state == :idle
    end

    test "quantize_to_beat returns {:ok, :now} when no clock", %{pid: pid} do
      result = GenServer.call(pid, {:quantize_to_beat, []})
      assert {:ok, :now} = result
    end
  end

  describe "handle_info messages" do
    setup do
      name = :"clock_info_test_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Clock.start_link(name: name)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "handles midi_device_connected", %{pid: pid} do
      send(pid, {:midi_device_connected, %{port_id: "input:0", name: "Test"}})
      assert Process.alive?(pid)
    end

    test "handles midi_device_disconnected", %{pid: pid} do
      send(pid, {:midi_device_disconnected, %{port_id: "input:0"}})
      assert Process.alive?(pid)
    end

    test "handles midi_message with clock tick", %{pid: pid} do
      send(pid, {:midi_message, "input:0", %{type: :clock}})
      assert Process.alive?(pid)
    end

    test "handles midi_message with start", %{pid: pid} do
      send(pid, {:midi_message, "input:0", %{type: :start}})
      # After start, transport should be :playing
      state = GenServer.call(pid, :get_transport_state)
      assert state == :playing
    end

    test "handles midi_message with stop", %{pid: pid} do
      send(pid, {:midi_message, "input:0", %{type: :start}})
      send(pid, {:midi_message, "input:0", %{type: :stop}})
      state = GenServer.call(pid, :get_transport_state)
      assert state == :stopped
    end

    test "handles midi_message with continue", %{pid: pid} do
      send(pid, {:midi_message, "input:0", %{type: :stop}})
      send(pid, {:midi_message, "input:0", %{type: :continue}})
      state = GenServer.call(pid, :get_transport_state)
      assert state == :playing
    end

    test "handles unknown messages", %{pid: pid} do
      send(pid, {:random_event, :data})
      assert Process.alive?(pid)
    end
  end

  describe "subscribe/0" do
    test "subscribes to midi:clock topic" do
      assert :ok = Clock.subscribe()
    end
  end
end
