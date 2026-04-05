defmodule SoundForge.MIDI.ActionExecutorActionsTest do
  @moduledoc """
  Tests for ActionExecutor action dispatch with real DB mappings.
  Exercises the private execute_action branches by creating MIDI mappings
  in the database and sending matching messages through the GenServer.
  """
  use SoundForge.DataCase

  alias SoundForge.MIDI.{ActionExecutor, Mappings}

  @device_name "Test MIDI Controller"
  @port_id "input:test_ae"

  setup do
    user = SoundForge.AccountsFixtures.user_fixture()

    # Create mappings for various actions
    actions = [
      %{action: :play, channel: 0, number: 1, midi_type: :note_on},
      %{action: :stop, channel: 0, number: 2, midi_type: :note_on},
      %{action: :next_track, channel: 0, number: 3, midi_type: :note_on},
      %{action: :prev_track, channel: 0, number: 4, midi_type: :note_on},
      %{action: :seek, channel: 0, number: 5, midi_type: :note_on},
      %{action: :stem_volume, channel: 0, number: 10, midi_type: :cc,
        params: %{"target" => "vocals", "track_id" => "track-123"}},
      %{action: :stem_solo, channel: 0, number: 11, midi_type: :cc,
        params: %{"stem" => "vocals", "track_id" => "track-123"}},
      %{action: :stem_mute, channel: 0, number: 12, midi_type: :cc,
        params: %{"stem" => "drums", "track_id" => "track-123"}},
      %{action: :bpm_tap, channel: 0, number: 20, midi_type: :note_on},
      %{action: :dj_play, channel: 1, number: 30, midi_type: :note_on,
        params: %{"deck" => "1"}},
      %{action: :dj_cue, channel: 1, number: 31, midi_type: :note_on,
        params: %{"deck" => "1", "slot" => "1"}},
      %{action: :dj_crossfader, channel: 1, number: 32, midi_type: :cc},
      %{action: :dj_loop_toggle, channel: 1, number: 33, midi_type: :note_on,
        params: %{"deck" => "1"}},
      %{action: :dj_loop_size, channel: 1, number: 34, midi_type: :cc,
        params: %{"deck" => "1", "beats" => "4.0"}},
      %{action: :dj_pitch, channel: 1, number: 35, midi_type: :cc,
        params: %{"deck" => "1"}},
      %{action: :pad_trigger, channel: 2, number: 40, midi_type: :note_on},
      %{action: :pad_volume, channel: 2, number: 41, midi_type: :cc},
      %{action: :pad_pitch, channel: 2, number: 42, midi_type: :cc},
      %{action: :pad_velocity, channel: 2, number: 43, midi_type: :cc},
      %{action: :pad_master_volume, channel: 2, number: 44, midi_type: :cc}
    ]

    for a <- actions do
      {:ok, _} =
        Mappings.create_mapping(
          Map.merge(
            %{user_id: user.id, device_name: @device_name},
            a
          )
        )
    end

    # Start executor with this user
    name = :"ae_actions_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = ActionExecutor.start_link(name: name, user_id: user.id)

    # Register the device
    send(pid, {:midi_device_connected, %{port_id: @port_id, name: @device_name}})
    Process.sleep(20)

    # Subscribe to action broadcasts
    Phoenix.PubSub.subscribe(SoundForge.PubSub, "midi:actions")
    Phoenix.PubSub.subscribe(SoundForge.PubSub, "dj:midi")
    Phoenix.PubSub.subscribe(SoundForge.PubSub, "sampler:midi")

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    %{pid: pid, user: user}
  end

  defp send_note(pid, channel, note, velocity \\ 127) do
    msg = %{type: :note_on, channel: channel, data: %{note: note, velocity: velocity}}
    send(pid, {:midi_message, @port_id, msg})
    Process.sleep(30)
  end

  defp send_cc(pid, channel, controller, value) do
    msg = %{type: :cc, channel: channel, data: %{controller: controller, value: value}}
    send(pid, {:midi_message, @port_id, msg})
    Process.sleep(30)
  end

  describe "transport actions" do
    test "dispatches :play action", %{pid: pid} do
      send_note(pid, 0, 1)
      assert_receive {:midi_action, :play, _}, 200
    end

    test "dispatches :stop action", %{pid: pid} do
      send_note(pid, 0, 2)
      assert_receive {:midi_action, :stop, _}, 200
    end

    test "dispatches :next_track action", %{pid: pid} do
      send_note(pid, 0, 3)
      assert_receive {:midi_action, :next_track, _}, 200
    end

    test "dispatches :prev_track action", %{pid: pid} do
      send_note(pid, 0, 4)
      assert_receive {:midi_action, :prev_track, _}, 200
    end

    test "dispatches :seek action", %{pid: pid} do
      send_note(pid, 0, 5)
      assert_receive {:midi_action, :seek, _}, 200
    end

    test "dispatches :bpm_tap action", %{pid: pid} do
      send_note(pid, 0, 20)
      assert_receive {:midi_action, :bpm_tap, _}, 200
    end
  end

  describe "stem actions" do
    test "dispatches :stem_volume with float value", %{pid: pid} do
      send_cc(pid, 0, 10, 64)
      assert_receive {:midi_action, :stem_volume, %{volume: v}}, 200
      assert is_float(v)
      assert_in_delta v, 0.504, 0.01
    end

    test "dispatches :stem_solo toggle", %{pid: pid} do
      send_cc(pid, 0, 11, 127)
      assert_receive {:midi_action, :stem_solo, %{soloed: true}}, 200
    end

    test "dispatches :stem_solo toggle off on second press", %{pid: pid} do
      send_cc(pid, 0, 11, 127)
      assert_receive {:midi_action, :stem_solo, %{soloed: true}}, 200
      send_cc(pid, 0, 11, 127)
      assert_receive {:midi_action, :stem_solo, %{soloed: false}}, 200
    end

    test "dispatches :stem_mute toggle", %{pid: pid} do
      send_cc(pid, 0, 12, 127)
      assert_receive {:midi_action, :stem_mute, %{muted: true}}, 200
    end
  end

  describe "DJ actions" do
    test "dispatches :dj_play on deck", %{pid: pid} do
      send_note(pid, 1, 30)
      assert_receive {:dj_play, 1}, 200
    end

    test "dispatches :dj_cue on deck", %{pid: pid} do
      send_note(pid, 1, 31)
      assert_receive {:dj_cue, 1, 1}, 200
    end

    test "dispatches :dj_crossfader", %{pid: pid} do
      send_cc(pid, 1, 32, 64)
      assert_receive {:dj_crossfader, cf}, 200
      assert is_integer(cf)
    end

    test "dispatches :dj_loop_toggle", %{pid: pid} do
      send_note(pid, 1, 33)
      assert_receive {:dj_loop_toggle, 1}, 200
    end

    test "dispatches :dj_loop_size", %{pid: pid} do
      send_cc(pid, 1, 34, 64)
      assert_receive {:dj_loop_size, 1, 4.0}, 200
    end

    test "dispatches :dj_pitch", %{pid: pid} do
      send_cc(pid, 1, 35, 64)
      assert_receive {:dj_pitch, 1, pitch}, 200
      assert is_float(pitch)
    end
  end

  describe "pad actions" do
    test "dispatches :pad_trigger", %{pid: pid} do
      send_note(pid, 2, 40, 100)
      assert_receive {:pad_trigger, %{pad_index: _, velocity: _}}, 200
    end

    test "dispatches :pad_volume CC", %{pid: pid} do
      send_cc(pid, 2, 41, 80)
      assert_receive {:pad_cc, %{param: :pad_volume, value: v}}, 200
      assert is_float(v)
    end

    test "dispatches :pad_pitch CC", %{pid: pid} do
      send_cc(pid, 2, 42, 64)
      assert_receive {:pad_cc, %{param: :pad_pitch}}, 200
    end

    test "dispatches :pad_velocity CC", %{pid: pid} do
      send_cc(pid, 2, 43, 100)
      assert_receive {:pad_cc, %{param: :pad_velocity}}, 200
    end

    test "dispatches :pad_master_volume CC", %{pid: pid} do
      send_cc(pid, 2, 44, 50)
      assert_receive {:pad_cc, %{param: :pad_master_volume}}, 200
    end
  end

  describe "edge cases" do
    test "no user_id skips action dispatch" do
      name = :"ae_no_user_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = ActionExecutor.start_link(name: name, user_id: nil)
      send(pid, {:midi_device_connected, %{port_id: @port_id, name: @device_name}})
      Process.sleep(10)
      send_note(pid, 0, 1)
      refute_receive {:midi_action, _, _}, 100
      GenServer.stop(pid)
    end

    test "unmatched MIDI message produces no action", %{pid: pid} do
      # Channel 15, note 127 -- no mapping exists
      send_note(pid, 15, 127)
      refute_receive {:midi_action, _, _}, 100
    end

    test "message from unknown device produces no action", %{pid: pid} do
      msg = %{type: :note_on, channel: 0, data: %{note: 1, velocity: 127}}
      send(pid, {:midi_message, "unknown_port", msg})
      Process.sleep(30)
      refute_receive {:midi_action, _, _}, 100
    end
  end
end
