defmodule SoundForge.OSC.ActionExecutorTest do
  use ExUnit.Case

  alias SoundForge.OSC.ActionExecutor

  describe "start_link/1" do
    test "starts the action executor" do
      assert {:ok, pid} = ActionExecutor.start_link(name: :ae_test_1)
      assert is_pid(pid)
      GenServer.stop(pid)
    end
  end

  describe "handle_info osc_message" do
    test "routes transport play to PubSub" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_play)
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_playback")

      send(pid, {:osc_message, %{address: "/transport/play", args: [1.0]}, {~c"127.0.0.1", 9000}})

      assert_receive {:action, :play}, 1000

      GenServer.stop(pid)
    end

    test "routes transport stop to PubSub" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_stop)
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_playback")

      send(pid, {:osc_message, %{address: "/transport/stop", args: [1.0]}, {~c"127.0.0.1", 9000}})

      assert_receive {:action, :stop}, 1000

      GenServer.stop(pid)
    end

    test "routes stem volume to PubSub" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_vol)
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_playback")

      send(pid, {:osc_message, %{address: "/stem/1/volume", args: [0.75]}, {~c"127.0.0.1", 9000}})

      assert_receive {:stem_volume, 1, 0.75}, 1000

      GenServer.stop(pid)
    end

    test "handles unknown messages without crashing" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_unknown)

      send(pid, {:osc_message, %{address: "/unknown/path", args: []}, {~c"127.0.0.1", 9000}})
      send(pid, :some_random_message)

      # Should still be alive
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "routes transport next to PubSub" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_next)
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_playback")

      send(pid, {:osc_message, %{address: "/transport/next", args: []}, {~c"127.0.0.1", 9000}})

      assert_receive {:action, :next_track}, 1000
      GenServer.stop(pid)
    end

    test "routes transport prev to PubSub" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_prev)
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_playback")

      send(pid, {:osc_message, %{address: "/transport/prev", args: []}, {~c"127.0.0.1", 9000}})

      assert_receive {:action, :prev_track}, 1000
      GenServer.stop(pid)
    end

    test "routes stem mute to PubSub" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_mute)
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_playback")

      send(pid, {:osc_message, %{address: "/stem/2/mute", args: [1.0]}, {~c"127.0.0.1", 9000}})

      assert_receive {:stem_mute, 2, true}, 1000
      GenServer.stop(pid)
    end

    test "routes stem solo to PubSub" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_solo)
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_playback")

      send(pid, {:osc_message, %{address: "/stem/3/solo", args: [1.0]}, {~c"127.0.0.1", 9000}})

      assert_receive {:stem_solo, 3, true}, 1000
      GenServer.stop(pid)
    end

    test "stem mute with value below 0.5 sends false" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_mute_off)
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_playback")

      send(pid, {:osc_message, %{address: "/stem/1/mute", args: [0.0]}, {~c"127.0.0.1", 9000}})

      assert_receive {:stem_mute, 1, false}, 1000
      GenServer.stop(pid)
    end

    test "unknown stem sub-address is handled" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_stem_unk)

      send(pid, {:osc_message, %{address: "/stem/1/unknown", args: [1.0]}, {~c"127.0.0.1", 9000}})

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "handle_info feedback messages" do
    test "handles stem_volume_changed feedback" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_fb_vol)

      send(pid, {:stem_volume_changed, "vocals", 80})

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "handles playback_state :playing" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_fb_play)

      send(pid, {:playback_state, :playing})

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "handles playback_state :stopped" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_fb_stop)

      send(pid, {:playback_state, :stopped})

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "handles playback_state unknown value" do
      {:ok, pid} = ActionExecutor.start_link(name: :ae_test_fb_other)

      send(pid, {:playback_state, :paused})

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
end
