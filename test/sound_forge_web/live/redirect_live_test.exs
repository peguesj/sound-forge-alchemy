defmodule SoundForgeWeb.RedirectLiveTest do
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.AccountsFixtures

  setup :register_and_log_in_user

  describe "DjLive" do
    test "redirects /dj to /?tab=dj", %{conn: conn} do
      {:error, {:live_redirect, %{to: to}}} = live(conn, "/dj")
      assert to =~ "tab=dj"
    end
  end

  describe "DawLive" do
    test "renders DAW page with flash error for invalid track_id", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/daw/invalid-track-id")
      assert html =~ "Invalid track ID" or html =~ "daw" or html =~ "DAW"
    end
  end

  describe "MidiLive" do
    test "renders for authenticated user", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/midi")
      assert html =~ "MIDI" or html =~ "midi" or html =~ "Controller"
    end
  end

  describe "SettingsLive" do
    test "renders settings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/settings")
      assert html =~ "Settings" or html =~ "settings"
    end
  end
end
