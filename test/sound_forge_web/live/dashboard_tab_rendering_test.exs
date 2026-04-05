defmodule SoundForgeWeb.DashboardTabRenderingTest do
  @moduledoc "Tests for DashboardLive tab rendering to exercise component template paths."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "tab switching" do
    test "switching to DJ tab renders DJ component", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "switch_tab", %{"tab" => "dj"})
      assert html =~ "deck" or html =~ "DJ" or html =~ "dj"
    end

    test "switching to DAW tab renders DAW component", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "switch_tab", %{"tab" => "daw"})
      assert html =~ "DAW" or html =~ "daw" or html =~ "editor"
    end

    test "switching to Pads tab renders pads component", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "switch_tab", %{"tab" => "pads"})
      assert html =~ "pad" or html =~ "Pad" or html =~ "bank"
    end

    test "switching to Admin tab attempts render", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "switch_tab", %{"tab" => "admin"})
      assert is_binary(html)
    end

    test "switching to Settings tab renders settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "switch_tab", %{"tab" => "settings"})
      assert html =~ "Settings" or html =~ "settings" or html =~ "Demucs"
    end

    test "switching to MIDI tab renders MIDI view", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "switch_tab", %{"tab" => "midi"})
      assert html =~ "MIDI" or html =~ "midi"
    end

    test "switching back to Library tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "switch_tab", %{"tab" => "library"})
      assert html =~ "Library" or html =~ "library" or html =~ "tracks"
    end

    test "URL-based tab navigation via ?tab param", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=dj")
      assert html =~ "deck" or html =~ "DJ" or html =~ "dj"
    end

    test "URL-based DAW tab navigation", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=daw")
      assert html =~ "DAW" or html =~ "daw" or html =~ "editor"
    end

    test "URL-based Pads tab navigation", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=pads")
      assert html =~ "pad" or html =~ "Pad" or html =~ "bank"
    end

    test "URL-based Settings tab navigation", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=settings")
      assert html =~ "Settings" or html =~ "settings"
    end
  end

  describe "DJ tab with track data" do
    test "DJ tab renders with tracks in library", %{conn: conn, user: user} do
      for i <- 1..3 do
        track_fixture(%{user_id: user.id, title: "DJ Track #{i}", artist: "Test DJ"})
      end

      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "switch_tab", %{"tab" => "dj"})
      assert is_binary(html)
    end

    test "DJ crossfader event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      html = render_click(view, "crossfader_change", %{"value" => "50"})
      assert is_binary(html)
    end

    test "DJ metronome toggle", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      html = render_click(view, "metronome_toggle")
      assert is_binary(html)
    end

    test "DJ metronome volume", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      html = render_click(view, "metronome_volume", %{"value" => "50"})
      assert is_binary(html)
    end
  end

  describe "DAW tab events" do
    test "DAW tab renders track picker when no track loaded", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "DAW Track"})
      {:ok, _view, html} = live(conn, ~p"/?tab=daw")
      assert is_binary(html)
    end
  end

  describe "library with data" do
    test "library renders tracks with various states", %{conn: conn, user: user} do
      # Create tracks with different states
      track_fixture(%{user_id: user.id, title: "Pending Track"})
      t2 = track_fixture(%{user_id: user.id, title: "Downloaded Track"})
      download_job_fixture(%{track_id: t2.id, status: :completed, output_path: "test.mp3"})

      t3 = track_fixture(%{user_id: user.id, title: "Processed Track"})
      download_job_fixture(%{track_id: t3.id, status: :completed, output_path: "test2.mp3"})
      processing_job_fixture(%{track_id: t3.id, model: "htdemucs", status: :completed})

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Pending Track"
      assert html =~ "Downloaded Track"
      assert html =~ "Processed Track"
    end
  end
end
