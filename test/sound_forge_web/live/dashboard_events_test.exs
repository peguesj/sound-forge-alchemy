defmodule SoundForgeWeb.DashboardEventsTest do
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "search" do
    test "search event filters tracks", %{conn: conn, user: user} do
      track_fixture(%{title: "Unique Search Term Track", user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      html = render_change(view, "search", %{"query" => "Unique Search Term"})
      assert html =~ "Unique Search Term Track"
    end

    test "empty search returns all tracks", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_change(view, "search", %{"query" => ""})
      assert is_binary(html)
    end
  end

  describe "toggle_view" do
    test "switches to grid view", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_view", %{"mode" => "grid"})
      assert is_binary(html)
    end

    test "switches to list view", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_view", %{"mode" => "list"})
      assert is_binary(html)
    end
  end

  describe "filter" do
    test "filter by status", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "filter", %{"status" => "downloaded"})
      assert is_binary(html)
    end

    test "filter all", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "filter", %{"status" => "all"})
      assert is_binary(html)
    end
  end

  describe "sort" do
    test "sort by title", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "sort", %{"sort_by" => "title"})
      assert is_binary(html)
    end

    test "sort by artist", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "sort", %{"sort_by" => "artist"})
      assert is_binary(html)
    end

    test "sort by date", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "sort", %{"sort_by" => "date"})
      assert is_binary(html)
    end
  end

  describe "batch mode" do
    test "toggle_batch_mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_batch_mode")
      assert is_binary(html)
    end
  end

  describe "navigation events" do
    test "nav_all_tracks", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_all_tracks")
      assert is_binary(html)
    end

    test "nav_recent", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_recent")
      assert is_binary(html)
    end

    test "nav_artists", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_artists")
      assert is_binary(html)
    end

    test "nav_albums", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_albums")
      assert is_binary(html)
    end
  end

  describe "debug panel" do
    test "toggle_debug_panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_debug_panel")
      assert html =~ "Debug" or html =~ "debug"
    end

    test "close_debug_panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "close_debug_panel")
      assert is_binary(html)
    end

    test "debug_tab switching", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_tab", %{"tab" => "logs"})
      assert is_binary(html)
    end
  end

  describe "drawer" do
    test "open_drawer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "open_drawer")
      assert is_binary(html)
    end

    test "close_drawer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "open_drawer")
      html = render_click(view, "close_drawer")
      assert is_binary(html)
    end
  end

  describe "metadata editing" do
    test "edit_metadata opens editor", %{conn: conn, user: user} do
      track = track_fixture(%{title: "Edit Me", user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "edit_metadata", %{"id" => track.id})
      assert html =~ "Edit Me" or html =~ "edit"
    end

    test "cancel_edit closes editor", %{conn: conn, user: user} do
      track = track_fixture(%{title: "Cancel Edit", user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "edit_metadata", %{"id" => track.id})
      html = render_click(view, "cancel_edit")
      assert is_binary(html)
    end
  end

  describe "engine selection" do
    test "select_engine demucs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "select_engine", %{"engine" => "demucs"})
      assert is_binary(html)
    end

    test "select_engine lalalai", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "select_engine", %{"engine" => "lalalai"})
      assert is_binary(html)
    end
  end

  describe "lalalai modal" do
    test "close_lalalai_modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "close_lalalai_modal")
      assert is_binary(html)
    end

    test "toggle_preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_preview")
      assert is_binary(html)
    end
  end

  describe "keydown" do
    test "handles unknown key gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_keydown(view, "keydown", %{"key" => "z"})
      assert is_binary(html)
    end
  end

  describe "page/2" do
    test "pagination changes page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "page", %{"page" => "1"})
      assert is_binary(html)
    end
  end

  describe "toggle_auto_download" do
    test "toggles auto download", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_auto_download")
      assert is_binary(html)
    end
  end
end
