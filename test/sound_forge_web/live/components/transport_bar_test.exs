defmodule SoundForgeWeb.Live.Components.TransportBarComponentTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.TransportBarComponent

  describe "render_component/2 library mode" do
    test "renders transport bar with default assigns" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-test",
          nav_tab: :library
        })

      assert html =~ "No Track"
      assert html =~ "SMPTE"
      assert html =~ "BPM"
      assert html =~ "00:00:00:00"
    end

    test "renders track info when provided" do
      track = %{title: "Test Song", artist: "Test Artist"}

      html =
        render_component(TransportBarComponent, %{
          id: "transport-test",
          nav_tab: :library,
          track: track
        })

      assert html =~ "Test Song"
      assert html =~ "Test Artist"
    end

    test "renders loop controls" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-test",
          nav_tab: :library
        })

      assert html =~ "IN"
      assert html =~ "OUT"
    end

    test "renders volume slider" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-test",
          nav_tab: :library
        })

      # Default volume is 80
      assert html =~ "80"
    end

    test "renders default BPM" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-test",
          nav_tab: :library
        })

      # Default BPM is 120.0
      assert html =~ "120.0"
    end
  end

  describe "render_component/2 DAW mode" do
    test "renders record button in DAW mode" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-daw",
          nav_tab: :daw
        })

      assert html =~ "transport_record"
    end

    test "renders time signature in DAW mode" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-daw",
          nav_tab: :daw
        })

      assert html =~ "4/4"
    end

    test "renders zoom controls in DAW mode" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-daw",
          nav_tab: :daw
        })

      assert html =~ "zoom_in"
      assert html =~ "zoom_out"
      assert html =~ "1x"
    end
  end

  describe "render_component/2 DJ mode" do
    test "renders deck selector in DJ mode" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-dj",
          nav_tab: :dj
        })

      assert html =~ "Deck 1"
      assert html =~ "Deck 2"
    end

    test "does not render record button in DJ mode" do
      html =
        render_component(TransportBarComponent, %{
          id: "transport-dj",
          nav_tab: :dj
        })

      refute html =~ "transport_record"
    end
  end
end
