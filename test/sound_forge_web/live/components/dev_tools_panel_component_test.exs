defmodule SoundForgeWeb.Live.Components.DevToolsPanelComponentTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.DevToolsPanelComponent

  describe "render_component/2" do
    test "renders collapsed by default" do
      html =
        render_component(DevToolsPanelComponent, %{
          id: "test-devtools",
          current_path: "/",
          assigns_count: 5
        })

      assert html =~ "test-devtools"
    end

    test "renders with current path info" do
      html =
        render_component(DevToolsPanelComponent, %{
          id: "test-devtools-2",
          current_path: "/admin",
          assigns_count: 10
        })

      assert html =~ "test-devtools-2"
    end
  end
end
