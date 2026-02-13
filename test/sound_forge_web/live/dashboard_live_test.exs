defmodule SoundForgeWeb.DashboardLiveTest do
  use SoundForgeWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders dashboard page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Sound Forge Alchemy"
    assert html =~ "Paste a Spotify URL"
  end

  test "has search input", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "input[name='query']")
  end

  test "has spotify url input", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "input[name='url']")
  end

  test "displays no tracks message initially", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "No tracks yet"
  end

  test "displays version number", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "v3.0.0"
  end
end
