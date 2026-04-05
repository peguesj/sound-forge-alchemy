defmodule SoundForgeWeb.DjInteractionsTest do
  @moduledoc """
  Tests DJ tab interactions to exercise DjTabComponent template branches.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "DJ deck controls" do
    test "play/pause deck 1", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Play Test"})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})

      html = render_click(view, "play_pause", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "play/pause deck 2", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Deck 2 Play"})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "2"})

      html = render_click(view, "play_pause", %{"deck" => "2"})
      assert html =~ "dj-tab"
    end

    test "volume change on deck 1", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "volume_change", %{"deck" => "1", "value" => "75"})
      assert html =~ "dj-tab"
    end

    test "volume change on deck 2", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "volume_change", %{"deck" => "2", "value" => "80"})
      assert html =~ "dj-tab"
    end

    test "sync deck tempo", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Sync Test"})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})

      html = render_click(view, "sync", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end
  end

  describe "DJ stem controls" do
    test "toggle stem mute", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_stem_mute", %{"deck" => "1", "stem" => "vocals"})
      assert html =~ "dj-tab"
    end

    test "toggle stem solo", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_stem_solo", %{"deck" => "1", "stem" => "drums"})
      assert html =~ "dj-tab"
    end

    test "stem volume change", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "stem_volume", %{"deck" => "1", "stem" => "bass", "value" => "60"})
      assert html =~ "dj-tab"
    end
  end

  describe "DJ EQ controls" do
    test "EQ adjustment", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "eq_change", %{"deck" => "1", "band" => "high", "value" => "1.5"})
      assert html =~ "dj-tab"
    end
  end

  describe "DJ transport" do
    test "loop toggle", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "loop_toggle", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "seek", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "seek", %{"deck" => "1", "position" => "30000"})
      assert html =~ "dj-tab"
    end
  end

  describe "DJ auto-mix" do
    test "auto mix toggle", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "auto_mix", %{})
      assert html =~ "dj-tab"
    end
  end
end
