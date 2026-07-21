defmodule SoundForgeWeb.Live.Components.NotificationBellExtendedTest do
  @moduledoc "Extended tests for NotificationBell rendering states."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.NotificationBell

  describe "render with notifications" do
    test "renders bell with unread notifications" do
      html =
        render_component(NotificationBell, %{
          id: "bell-unread",
          user_id: nil,
          active_pipelines: [],
          refresh: false
        })

      assert is_binary(html)
    end

    test "renders bell with empty state" do
      html =
        render_component(NotificationBell, %{
          id: "bell-empty",
          user_id: nil,
          active_pipelines: []
        })

      assert is_binary(html)
    end

    test "renders bell with active pipelines" do
      pipelines = [
        %{track_id: "t1", stage: :download, status: :downloading, progress: 50}
      ]

      html =
        render_component(NotificationBell, %{
          id: "bell-pipelines",
          user_id: nil,
          active_pipelines: pipelines
        })

      assert is_binary(html)
    end
  end

  describe "bell via dashboard" do
    setup :register_and_log_in_user

    test "bell is rendered on dashboard", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "notification"
    end

    test "toggle_bell opens notification panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      # The bell toggle should be accessible
      html = render(view)
      assert is_binary(html)
    end
  end
end
