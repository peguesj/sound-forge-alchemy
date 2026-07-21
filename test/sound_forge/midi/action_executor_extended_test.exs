defmodule SoundForge.MIDI.ActionExecutorExtendedTest do
  @moduledoc "Extended tests for MIDI ActionExecutor GenServer and helpers."
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.ActionExecutor

  describe "cc_to_float/1" do
    test "converts 0 to 0.0" do
      assert ActionExecutor.cc_to_float(0) == 0.0
    end

    test "converts 127 to 1.0" do
      assert ActionExecutor.cc_to_float(127) == 1.0
    end

    test "converts 64 to midpoint" do
      result = ActionExecutor.cc_to_float(64)
      assert result > 0.49 and result < 0.52
    end

    test "clamps negative values to 0.0" do
      assert ActionExecutor.cc_to_float(-5) == 0.0
    end

    test "clamps values above 127 to 1.0" do
      assert ActionExecutor.cc_to_float(200) == 1.0
    end

    test "converts 1 to small positive" do
      result = ActionExecutor.cc_to_float(1)
      assert result > 0.0 and result < 0.02
    end

    test "converts 126 to near 1.0" do
      result = ActionExecutor.cc_to_float(126)
      assert result > 0.98 and result <= 1.0
    end
  end

  describe "start_link/1" do
    test "starts with custom name" do
      name = :"test_executor_#{System.unique_integer([:positive])}"
      {:ok, pid} = ActionExecutor.start_link(name: name, user_id: nil)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts without user_id" do
      name = :"test_executor_no_uid_#{System.unique_integer([:positive])}"
      {:ok, pid} = ActionExecutor.start_link(name: name)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "handles unknown messages gracefully" do
      name = :"test_executor_msg_#{System.unique_integer([:positive])}"
      {:ok, pid} = ActionExecutor.start_link(name: name, user_id: nil)
      send(pid, :some_random_message)
      Process.sleep(10)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "handles midi_device_connected" do
      name = :"test_executor_connect_#{System.unique_integer([:positive])}"
      {:ok, pid} = ActionExecutor.start_link(name: name, user_id: nil)

      send(
        pid,
        {:midi_device_connected, %{port_id: "input:99", name: "Test MIDI", direction: :input}}
      )

      Process.sleep(10)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "handles midi_device_disconnected" do
      name = :"test_executor_disconnect_#{System.unique_integer([:positive])}"
      {:ok, pid} = ActionExecutor.start_link(name: name, user_id: nil)

      send(
        pid,
        {:midi_device_disconnected, %{port_id: "input:99", name: "Test MIDI", direction: :input}}
      )

      Process.sleep(10)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "handles midi_message with no mapping" do
      name = :"test_executor_nomatch_#{System.unique_integer([:positive])}"
      {:ok, pid} = ActionExecutor.start_link(name: name, user_id: nil)
      send(pid, {:midi_message, "input:99", %{type: :cc, channel: 0, number: 50, value: 64}})
      Process.sleep(10)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
end
