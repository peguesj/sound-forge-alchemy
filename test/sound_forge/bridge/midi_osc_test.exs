defmodule SoundForge.Bridge.MidiOscTest do
  use ExUnit.Case

  alias SoundForge.Bridge.MidiOsc

  setup do
    name = :"midi_osc_test_#{System.unique_integer([:positive])}"
    {:ok, pid} = MidiOsc.start_link(name: name, touchosc_host: "127.0.0.1", touchosc_port: 9999)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    %{server: name}
  end

  describe "start_link/1" do
    test "starts the bridge GenServer", %{server: server} do
      state = MidiOsc.get_state(server)
      assert state.enabled == true
      assert state.touchosc_host == "127.0.0.1"
      assert state.touchosc_port == 9999
    end
  end

  describe "set_mapping/2" do
    test "updates the mapping table", %{server: server} do
      custom = %{"/custom/path" => %{type: :cc, channel: 1, number: 99, value: 0}}
      assert :ok = MidiOsc.set_mapping(custom, server)

      state = MidiOsc.get_state(server)
      assert state.mappings == custom
    end
  end

  describe "set_touchosc_target/3" do
    test "updates host and port", %{server: server} do
      assert :ok = MidiOsc.set_touchosc_target("10.0.0.1", 8000, server)
      state = MidiOsc.get_state(server)
      assert state.touchosc_host == "10.0.0.1"
      assert state.touchosc_port == 8000
    end
  end

  describe "set_enabled/2" do
    test "disables the bridge", %{server: server} do
      assert :ok = MidiOsc.set_enabled(false, server)
      state = MidiOsc.get_state(server)
      assert state.enabled == false
    end

    test "re-enables the bridge", %{server: server} do
      MidiOsc.set_enabled(false, server)
      assert :ok = MidiOsc.set_enabled(true, server)
      state = MidiOsc.get_state(server)
      assert state.enabled == true
    end
  end

  describe "handle_info/2" do
    test "ignores osc_message when disabled", %{server: server} do
      MidiOsc.set_enabled(false, server)
      msg = {:osc_message, %{address: "/transport/play", args: [1.0]}, {"127.0.0.1", 8000}}
      send(server, msg)
      # Should not crash
      state = MidiOsc.get_state(server)
      assert state.enabled == false
    end

    test "handles unknown messages without crashing", %{server: server} do
      send(server, {:unknown_message, :test})
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles osc_message for stem volume", %{server: server} do
      msg = {:osc_message, %{address: "/stem/1/volume", args: [0.75]}, {"127.0.0.1", 8000}}
      send(server, msg)
      # Should not crash, bridge translates to MIDI CC
      state = MidiOsc.get_state(server)
      assert state.enabled == true
    end

    test "handles osc_message for stem mute", %{server: server} do
      msg = {:osc_message, %{address: "/stem/2/mute", args: [1.0]}, {"127.0.0.1", 8000}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles osc_message for stem solo", %{server: server} do
      msg = {:osc_message, %{address: "/stem/3/solo", args: [1.0]}, {"127.0.0.1", 8000}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles osc_message for pad trigger", %{server: server} do
      msg = {:osc_message, %{address: "/pad/5", args: [1.0]}, {"127.0.0.1", 8000}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles osc_message for transport play", %{server: server} do
      msg = {:osc_message, %{address: "/transport/play", args: [1.0]}, {"127.0.0.1", 8000}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles osc_message for transport stop", %{server: server} do
      msg = {:osc_message, %{address: "/transport/stop", args: [1.0]}, {"127.0.0.1", 8000}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles osc_message for transport next", %{server: server} do
      msg = {:osc_message, %{address: "/transport/next", args: [1.0]}, {"127.0.0.1", 8000}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles osc_message for transport prev", %{server: server} do
      msg = {:osc_message, %{address: "/transport/prev", args: [1.0]}, {"127.0.0.1", 8000}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles osc_message for unknown address with custom mapping", %{server: server} do
      custom_mapping = %{"/custom/fader" => %{type: :cc, channel: 0, number: 50, value: 64}}
      MidiOsc.set_mapping(custom_mapping, server)
      msg = {:osc_message, %{address: "/custom/fader", args: [0.5]}, {"127.0.0.1", 8000}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles osc_message for unmapped address", %{server: server} do
      msg = {:osc_message, %{address: "/unknown/path", args: [0.5]}, {"127.0.0.1", 8000}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles midi_state_change for stem volume CC", %{server: server} do
      msg = {:midi_state_change, %{type: :cc, channel: 1, number: 7, value: 100}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles midi_state_change for stem mute CC", %{server: server} do
      msg = {:midi_state_change, %{type: :cc, channel: 1, number: 17, value: 127}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles midi_state_change for stem solo CC", %{server: server} do
      msg = {:midi_state_change, %{type: :cc, channel: 1, number: 33, value: 64}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "handles midi_state_change for unrecognized CC", %{server: server} do
      msg = {:midi_state_change, %{type: :cc, channel: 0, number: 99, value: 50}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert is_map(state)
    end

    test "ignores midi_state_change when disabled", %{server: server} do
      MidiOsc.set_enabled(false, server)
      msg = {:midi_state_change, %{type: :cc, channel: 1, number: 7, value: 100}}
      send(server, msg)
      state = MidiOsc.get_state(server)
      assert state.enabled == false
    end
  end

  describe "get_state/1" do
    test "returns full state map", %{server: server} do
      state = MidiOsc.get_state(server)
      assert Map.has_key?(state, :enabled)
      assert Map.has_key?(state, :touchosc_host)
      assert Map.has_key?(state, :touchosc_port)
      assert Map.has_key?(state, :mappings)
    end
  end
end
