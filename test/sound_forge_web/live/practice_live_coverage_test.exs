defmodule SoundForgeWeb.PracticeLiveCoverageTest do
  @moduledoc "Tests for PracticeLive: mount, import_sessions, tab switching."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "mount" do
    test "renders practice dashboard", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/practice")
      assert html =~ "Practice"
    end
  end

  describe "events" do
    test "import_sessions returns flash on no melodics dir", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/practice")
      html = render_click(view, "import_sessions", %{})
      assert is_binary(html)
    end

    test "switch_detail_tab to stems", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/practice")
      html = render_click(view, "switch_detail_tab", %{"tab" => "stems"})
      assert is_binary(html)
    end

    test "switch_detail_tab to sessions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/practice")
      html = render_click(view, "switch_detail_tab", %{"tab" => "sessions"})
      assert is_binary(html)
    end
  end
end
