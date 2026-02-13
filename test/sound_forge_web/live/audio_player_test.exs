defmodule SoundForgeWeb.AudioPlayerLiveTest do
  use SoundForgeWeb.ConnCase

  test "module compiles" do
    assert Code.ensure_loaded?(SoundForgeWeb.AudioPlayerLive)
  end

  describe "component initialization" do
    test "initializes with default state" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}}
      }

      {:ok, socket} = SoundForgeWeb.AudioPlayerLive.mount(socket)

      assert socket.assigns.playing == false
      assert socket.assigns.current_time == 0
      assert socket.assigns.duration == 0
      assert socket.assigns.master_volume == 80
      assert socket.assigns.stem_volumes == %{}
      assert socket.assigns.muted_stems == MapSet.new()
      assert socket.assigns.solo_stem == nil
    end
  end

  describe "event handling" do
    setup do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          playing: false,
          current_time: 0,
          duration: 0,
          master_volume: 80,
          stem_volumes: %{"vocals" => 100, "drums" => 100},
          muted_stems: MapSet.new(),
          solo_stem: nil,
          __changed__: %{}
        }
      }

      {:ok, socket: socket}
    end

    test "toggle_play changes playing state", %{socket: socket} do
      {:noreply, updated_socket} =
        SoundForgeWeb.AudioPlayerLive.handle_event("toggle_play", %{}, socket)

      assert updated_socket.assigns.playing == true

      {:noreply, updated_socket} =
        SoundForgeWeb.AudioPlayerLive.handle_event("toggle_play", %{}, updated_socket)

      assert updated_socket.assigns.playing == false
    end

    test "master_volume updates volume level", %{socket: socket} do
      {:noreply, updated_socket} =
        SoundForgeWeb.AudioPlayerLive.handle_event("master_volume", %{"level" => "50"}, socket)

      assert updated_socket.assigns.master_volume == 50
    end

    test "stem_volume updates individual stem volume", %{socket: socket} do
      {:noreply, updated_socket} =
        SoundForgeWeb.AudioPlayerLive.handle_event(
          "stem_volume",
          %{"level" => "75", "stem" => "vocals"},
          socket
        )

      assert updated_socket.assigns.stem_volumes["vocals"] == 75
    end

    test "toggle_stem adds stem to muted set", %{socket: socket} do
      {:noreply, updated_socket} =
        SoundForgeWeb.AudioPlayerLive.handle_event("toggle_stem", %{"stem" => "vocals"}, socket)

      assert MapSet.member?(updated_socket.assigns.muted_stems, "vocals")
    end

    test "toggle_stem removes stem from muted set when already muted", %{socket: socket} do
      socket = %{socket | assigns: Map.put(socket.assigns, :muted_stems, MapSet.new(["vocals"]))}

      {:noreply, updated_socket} =
        SoundForgeWeb.AudioPlayerLive.handle_event("toggle_stem", %{"stem" => "vocals"}, socket)

      refute MapSet.member?(updated_socket.assigns.muted_stems, "vocals")
    end

    test "solo_stem sets solo stem", %{socket: socket} do
      {:noreply, updated_socket} =
        SoundForgeWeb.AudioPlayerLive.handle_event("solo_stem", %{"stem" => "vocals"}, socket)

      assert updated_socket.assigns.solo_stem == "vocals"
    end

    test "solo_stem toggles off when same stem clicked", %{socket: socket} do
      socket = %{socket | assigns: Map.put(socket.assigns, :solo_stem, "vocals")}

      {:noreply, updated_socket} =
        SoundForgeWeb.AudioPlayerLive.handle_event("solo_stem", %{"stem" => "vocals"}, socket)

      assert updated_socket.assigns.solo_stem == nil
    end

    test "player_ready updates duration", %{socket: socket} do
      {:noreply, updated_socket} =
        SoundForgeWeb.AudioPlayerLive.handle_event(
          "player_ready",
          %{"duration" => 180.5},
          socket
        )

      assert updated_socket.assigns.duration == 180.5
    end

    test "time_update updates current_time", %{socket: socket} do
      {:noreply, updated_socket} =
        SoundForgeWeb.AudioPlayerLive.handle_event("time_update", %{"time" => 30.2}, socket)

      assert updated_socket.assigns.current_time == 30.2
    end
  end

  describe "update/2" do
    test "assigns new values and initializes stem volumes" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          stem_volumes: %{},
          playing: false,
          current_time: 0,
          duration: 0,
          master_volume: 80,
          muted_stems: MapSet.new(),
          solo_stem: nil
        }
      }

      stems = [
        %{stem_type: :vocals, file_path: "/tmp/vocals.wav", file_size: 1000},
        %{stem_type: :drums, file_path: "/tmp/drums.wav", file_size: 1000}
      ]

      new_assigns = %{stems: stems, id: "player-1", track: %{id: "abc"}}
      {:ok, updated_socket} = SoundForgeWeb.AudioPlayerLive.update(new_assigns, socket)

      assert updated_socket.assigns.id == "player-1"
      assert updated_socket.assigns.stem_volumes["vocals"] == 100
      assert updated_socket.assigns.stem_volumes["drums"] == 100
    end
  end
end
