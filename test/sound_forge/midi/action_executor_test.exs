defmodule SoundForge.MIDI.ActionExecutorTest do
  @moduledoc """
  Tests for MIDI.ActionExecutor pure functions and GenServer callbacks.
  """
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.ActionExecutor

  describe "cc_to_float/1" do
    test "0 maps to 0.0" do
      assert ActionExecutor.cc_to_float(0) == 0.0
    end

    test "127 maps to 1.0" do
      assert ActionExecutor.cc_to_float(127) == 1.0
    end

    test "64 maps to approximately 0.5" do
      result = ActionExecutor.cc_to_float(64)
      assert result > 0.49 and result < 0.51
    end

    test "values above 127 clamp to 1.0" do
      assert ActionExecutor.cc_to_float(200) == 1.0
      assert ActionExecutor.cc_to_float(255) == 1.0
    end

    test "non-integer returns 0.0" do
      assert ActionExecutor.cc_to_float(nil) == 0.0
      assert ActionExecutor.cc_to_float(-1) == 0.0
    end

    test "1 returns small positive value" do
      result = ActionExecutor.cc_to_float(1)
      assert result > 0.0 and result < 0.01
    end

    test "126 returns value close to 1.0" do
      result = ActionExecutor.cc_to_float(126)
      assert result > 0.99 and result <= 1.0
    end

    test "returns float type for all valid inputs" do
      for v <- [0, 1, 32, 63, 64, 96, 126, 127] do
        assert is_float(ActionExecutor.cc_to_float(v))
      end
    end

    test "monotonically increasing across range" do
      values = Enum.map(0..127, &ActionExecutor.cc_to_float/1)
      pairs = Enum.zip(values, tl(values))
      Enum.each(pairs, fn {a, b} -> assert a <= b end)
    end

    test "handles atom input" do
      assert ActionExecutor.cc_to_float(:foo) == 0.0
    end

    test "handles list input" do
      assert ActionExecutor.cc_to_float([1, 2]) == 0.0
    end

    test "handles map input" do
      assert ActionExecutor.cc_to_float(%{}) == 0.0
    end
  end

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(ActionExecutor)
    end

    test "start_link/1 is defined" do
      assert {:start_link, 1} in ActionExecutor.__info__(:functions)
    end

    test "subscribe/0 is defined" do
      assert {:subscribe, 0} in ActionExecutor.__info__(:functions)
    end
  end

  describe "GenServer lifecycle" do
    setup do
      name = :"ae_test_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = ActionExecutor.start_link(name: name, user_id: nil)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "starts and runs", %{pid: pid} do
      assert Process.alive?(pid)
    end

    test "handles device connected message", %{pid: pid} do
      send(pid, {:midi_device_connected, %{port_id: "input:0", name: "Test Device"}})
      assert Process.alive?(pid)
    end

    test "handles device disconnected message", %{pid: pid} do
      # Connect then disconnect
      send(pid, {:midi_device_connected, %{port_id: "input:0", name: "Test Device"}})
      send(pid, {:midi_device_disconnected, %{port_id: "input:0"}})
      assert Process.alive?(pid)
    end

    test "handles midi_message from unknown device", %{pid: pid} do
      send(
        pid,
        {:midi_message, "unknown_port",
         %{type: :cc, channel: 0, data: %{controller: 1, value: 64}}}
      )

      assert Process.alive?(pid)
    end

    test "handles unknown message", %{pid: pid} do
      send(pid, {:some_random_event, :data})
      assert Process.alive?(pid)
    end
  end

  describe "subscribe/0" do
    test "subscribes calling process to actions topic" do
      assert :ok = ActionExecutor.subscribe()
    end
  end
end
