defmodule SoundForgeWeb.Live.Components.TransportBarEventsTest do
  @moduledoc "Tests for TransportBarComponent with various rendering states."
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.TransportBarComponent

  describe "render with playing state" do
    test "renders playing state controls" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-play",
          nav_tab: :library,
          playing: true,
          current_time: 65.5,
          duration: 240.0,
          bpm: 128.0,
          volume: 90
        })

      assert is_binary(html)
    end

    test "renders stopped state" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-stop",
          nav_tab: :library,
          playing: false,
          current_time: 0,
          duration: 0
        })

      assert html =~ "00:00:00:00"
      assert is_binary(html)
    end
  end

  describe "render with loop enabled" do
    test "renders active loop markers" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-loop",
          nav_tab: :library,
          loop_enabled: true,
          loop_in: 10.0,
          loop_out: 30.0
        })

      assert html =~ "IN"
      assert html =~ "OUT"
      assert is_binary(html)
    end

    test "renders loop disabled state" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-noloop",
          nav_tab: :library,
          loop_enabled: false
        })

      assert html =~ "IN"
      assert is_binary(html)
    end
  end

  describe "render with recording" do
    test "renders recording active in DAW mode" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-rec",
          nav_tab: :daw,
          recording: true,
          playing: true
        })

      assert html =~ "transport_record"
      assert is_binary(html)
    end
  end

  describe "render with different track info" do
    test "renders with long track title" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-long",
          nav_tab: :library,
          track: %{
            title: "A Very Long Track Title That Might Overflow",
            artist: "Long Artist Name"
          }
        })

      assert html =~ "A Very Long Track"
      assert is_binary(html)
    end

    test "renders with nil track" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-nil",
          nav_tab: :library,
          track: nil
        })

      assert html =~ "No Track"
      assert is_binary(html)
    end
  end

  describe "render with DJ active deck" do
    test "renders deck 1 active" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-dj1",
          nav_tab: :dj,
          active_deck: 1
        })

      assert html =~ "Deck 1"
      assert is_binary(html)
    end

    test "renders deck 2 active" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-dj2",
          nav_tab: :dj,
          active_deck: 2
        })

      assert html =~ "Deck 2"
      assert is_binary(html)
    end
  end

  describe "render with different zoom levels" do
    test "renders zoom 2x in DAW mode" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-zoom",
          nav_tab: :daw,
          zoom_level: 2.0
        })

      assert html =~ "2"
      assert is_binary(html)
    end
  end

  describe "render with different volumes" do
    test "renders muted volume" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-mute",
          nav_tab: :library,
          volume: 0
        })

      assert is_binary(html)
    end

    test "renders max volume" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-max",
          nav_tab: :library,
          volume: 100
        })

      assert html =~ "100"
      assert is_binary(html)
    end
  end

  describe "render with pads tab" do
    test "renders transport for pads mode" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-pads",
          nav_tab: :pads
        })

      assert is_binary(html)
    end
  end
end
