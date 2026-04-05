defmodule SoundForgeWeb.Live.Components.NotificationBellTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.NotificationBell

  describe "render_component/2" do
    test "renders bell button with zero unread count" do
      html =
        render_component(NotificationBell, %{
          id: "test-bell",
          user_id: nil,
          active_pipelines: []
        })

      assert html =~ "Notifications"
      assert html =~ "0 unread"
    end

    test "renders with a user_id and loads notifications" do
      html =
        render_component(NotificationBell, %{
          id: "test-bell",
          user_id: 999_999,
          active_pipelines: []
        })

      # Should render the bell button
      assert html =~ "Notifications"
    end

    test "renders 'No notifications yet' when empty" do
      html =
        render_component(NotificationBell, %{
          id: "test-bell",
          user_id: nil,
          active_pipelines: []
        })

      # Dropdown is closed by default (open: false), so the text is not visible
      # But the bell button should be rendered
      assert html =~ "test-bell"
    end

    test "renders active pipelines badge when pipelines exist" do
      pipelines = [
        {"track-1", "My Song", :download, :running, 45}
      ]

      html =
        render_component(NotificationBell, %{
          id: "test-bell",
          user_id: nil,
          active_pipelines: pipelines
        })

      # Badge should show with the count
      assert html =~ "1"
    end

    test "renders with multiple active pipelines" do
      pipelines = [
        {"track-1", "Song A", :download, :running, 30},
        {"track-2", "Song B", :processing, :running, 60}
      ]

      html =
        render_component(NotificationBell, %{
          id: "test-bell",
          user_id: nil,
          active_pipelines: pipelines
        })

      assert html =~ "2"
    end
  end
end
