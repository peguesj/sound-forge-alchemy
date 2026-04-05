defmodule SoundForgeWeb.Live.Components.MidiOscStatusBarTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.MidiOscStatusBar

  describe "status_bar/1" do
    test "renders with defaults" do
      html =
        render_component(&MidiOscStatusBar.status_bar/1,
          midi_device_count: 0,
          osc_active: false,
          touchosc_target: nil,
          mpc_device_name: nil,
          message_rate: 0,
          collapsed: false
        )

      assert html =~ "OSC"
    end

    test "renders with active devices" do
      html =
        render_component(&MidiOscStatusBar.status_bar/1,
          midi_device_count: 2,
          osc_active: true,
          touchosc_target: "192.168.1.100:9000",
          mpc_device_name: "MPC Live II",
          message_rate: 42,
          collapsed: false
        )

      assert html =~ "2"
      assert html =~ "bg-green-500"
      assert html =~ "192.168.1.100:9000"
      assert html =~ "MPC Live II"
    end

    test "renders collapsed mode" do
      html =
        render_component(&MidiOscStatusBar.status_bar/1,
          midi_device_count: 0,
          osc_active: false,
          touchosc_target: nil,
          mpc_device_name: nil,
          message_rate: 0,
          collapsed: true
        )

      assert html =~ "hidden"
    end
  end
end
