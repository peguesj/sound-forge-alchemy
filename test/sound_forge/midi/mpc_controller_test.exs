defmodule SoundForge.MIDI.MPCControllerTest do
  @moduledoc "Tests for MIDI.MPCController GenServer."
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.MPCController

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(MPCController)
    end

    test "start_link/1 is exported" do
      assert {:start_link, 1} in MPCController.__info__(:functions)
    end

    test "set_mode/2 is exported" do
      assert {:set_mode, 2} in MPCController.__info__(:functions)
    end

    test "get_mode/1 is exported" do
      assert {:get_mode, 1} in MPCController.__info__(:functions)
    end

    test "set_pad_stem_map/2 is exported" do
      assert {:set_pad_stem_map, 2} in MPCController.__info__(:functions)
    end

    test "implements GenServer" do
      behaviours =
        MPCController.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert GenServer in behaviours
    end
  end

  describe "GenServer lifecycle" do
    setup do
      name = :"mpc_ctrl_test_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = MPCController.start_link(name: name, mode: :toggle)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "starts with configured mode", %{pid: pid} do
      mode = GenServer.call(pid, :get_mode)
      assert mode == :toggle
    end

    test "set_mode changes mode to hold", %{pid: pid} do
      GenServer.call(pid, {:set_mode, :hold})
      assert GenServer.call(pid, :get_mode) == :hold
    end

    test "set_mode changes mode to toggle", %{pid: pid} do
      GenServer.call(pid, {:set_mode, :hold})
      GenServer.call(pid, {:set_mode, :toggle})
      assert GenServer.call(pid, :get_mode) == :toggle
    end

    test "set_pad_stem_map updates mapping", %{pid: pid} do
      result = GenServer.call(pid, {:set_pad_stem_map, %{0 => 3, 1 => 2}})
      assert result == :ok
    end
  end

  describe "handle_info messages" do
    setup do
      name = :"mpc_info_test_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = MPCController.start_link(name: name, mode: :hold)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "handles midi_message note_on from unknown port", %{pid: pid} do
      send(pid, {:midi_message, "unknown_port", %{type: :note_on, data: %{note: 36, velocity: 100}}})
      assert Process.alive?(pid)
    end

    test "handles midi_message note_off from unknown port", %{pid: pid} do
      send(pid, {:midi_message, "unknown_port", %{type: :note_off, data: %{note: 36}}})
      assert Process.alive?(pid)
    end

    test "handles midi_message with other type", %{pid: pid} do
      send(pid, {:midi_message, "port:0", %{type: :cc, data: %{controller: 1, value: 64}}})
      assert Process.alive?(pid)
    end

    test "handles midi_device_connected with non-MPC device", %{pid: pid} do
      send(pid, {:midi_device_connected, %{name: "Random MIDI Keyboard", port_id: "input:5"}})
      assert Process.alive?(pid)
    end

    test "handles midi_device_disconnected for unknown device", %{pid: pid} do
      send(pid, {:midi_device_disconnected, %{port_id: "input:99"}})
      assert Process.alive?(pid)
    end

    test "handles stem_state_changed", %{pid: pid} do
      send(pid, {:stem_state_changed, 0, :playing})
      assert Process.alive?(pid)
    end

    test "handles unknown messages", %{pid: pid} do
      send(pid, {:random_event, :test})
      assert Process.alive?(pid)
    end
  end
end
