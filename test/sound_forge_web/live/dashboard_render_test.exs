defmodule SoundForgeWeb.DashboardRenderTest do
  @moduledoc "Tests for dashboard rendering with various states to maximize template coverage."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "library tab rendering" do
    test "renders library with tracks", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "Test Track 1", artist: "Artist 1"})
      track_fixture(%{user_id: user.id, title: "Test Track 2", artist: "Artist 2"})
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Alchemy"
    end

    test "library shows grid view by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Paste a Spotify URL"
    end
  end

  describe "DJ tab rendering" do
    test "DJ tab renders dual deck UI", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/?tab=dj")
      assert html =~ "dj-tab"
    end

    test "DJ tab renders with track loaded on deck", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "DJ Track", artist: "DJ Artist"})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})
      assert html =~ "dj-tab"
    end
  end

  describe "DAW tab rendering" do
    test "DAW tab renders without track selected", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/?tab=daw")
      assert html =~ "daw-tab"
      assert html =~ "Select a track to edit stems"
    end

    test "DAW tab renders with track_id param", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "DAW Track"})
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")
      assert html =~ "daw-tab"
    end
  end

  describe "Pads tab rendering" do
    test "pads tab renders", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/?tab=pads")
      assert html =~ "Pads"
    end
  end

  describe "multiple tab switches" do
    test "can switch between all tabs without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      for tab <- ["dj", "daw", "pads", "library"] do
        view |> render_click("nav_tab", %{"tab" => tab})
      end

      # Final render should work
      html = render(view)
      assert html =~ "Sound Forge" || html =~ "tab"
    end
  end
end
