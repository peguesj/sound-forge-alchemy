defmodule SoundForgeWeb.Live.Components.MobileDrawerTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.MobileDrawer

  describe "mobile_drawer/1" do
    test "renders nothing when not open" do
      html = render_component(&MobileDrawer.mobile_drawer/1, open: false, nav_context: :library)
      refute html =~ "mobile-drawer"
    end

    test "renders drawer when open" do
      html = render_component(&MobileDrawer.mobile_drawer/1, open: true, nav_context: :library)
      assert html =~ "mobile-drawer"
      assert html =~ "Alchemy"
      assert html =~ "close_drawer"
    end
  end
end
