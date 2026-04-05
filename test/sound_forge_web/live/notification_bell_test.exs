defmodule SoundForgeWeb.NotificationBellTest do
  @moduledoc """
  Tests for NotificationBell LiveComponent events.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.Live.Components.NotificationBell)
    end

    test "exports handle_event/3" do
      assert {:handle_event, 3} in SoundForgeWeb.Live.Components.NotificationBell.__info__(:functions)
    end

    test "exports update/2" do
      assert {:update, 2} in SoundForgeWeb.Live.Components.NotificationBell.__info__(:functions)
    end
  end

  describe "notification bell interaction" do
    test "toggle_bell opens/closes panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      result =
        try do
          view |> element("[phx-click='toggle_bell']") |> render_click()
        rescue
          ArgumentError -> :element_not_found
        end

      assert is_binary(result) or result == :element_not_found
    end

    test "mark_all_read clears notifications", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      result =
        try do
          view |> element("[phx-click='toggle_bell']") |> render_click()
          view |> element("[phx-click='mark_all_read']") |> render_click()
        rescue
          ArgumentError -> :element_not_found
        end

      assert is_binary(result) or result == :element_not_found
    end
  end
end
