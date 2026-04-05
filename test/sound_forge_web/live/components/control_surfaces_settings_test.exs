defmodule SoundForgeWeb.Live.Components.ControlSurfacesSettingsTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.ControlSurfacesSettings

  describe "control_surfaces/1" do
    test "renders OSC tab by default" do
      html =
        render_component(&ControlSurfacesSettings.control_surfaces/1,
          active_tab: :osc,
          osc_config: %{port: 8000, target_host: "", target_port: 9000, enabled: false},
          midi_devices: [],
          mpc_devices: [],
          bridge_enabled: false
        )

      assert html =~ "Control Surfaces"
      assert html =~ "OSC Server"
      assert html =~ "Server Port"
    end

    test "renders MIDI tab" do
      html =
        render_component(&ControlSurfacesSettings.control_surfaces/1,
          active_tab: :midi,
          osc_config: %{port: 8000, target_host: "", target_port: 9000, enabled: false},
          midi_devices: [],
          mpc_devices: [],
          bridge_enabled: false
        )

      assert html =~ "Control Surfaces"
    end

    test "renders MPC tab" do
      html =
        render_component(&ControlSurfacesSettings.control_surfaces/1,
          active_tab: :mpc,
          osc_config: %{port: 8000, target_host: "", target_port: 9000, enabled: false},
          midi_devices: [],
          mpc_devices: [],
          bridge_enabled: false
        )

      assert html =~ "Control Surfaces"
    end
  end
end
