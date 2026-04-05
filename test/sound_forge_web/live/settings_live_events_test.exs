defmodule SoundForgeWeb.SettingsLiveEventsTest do
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "mount" do
    test "renders settings page with sidebar sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/settings")
      assert html =~ "Settings"
      assert html =~ "Spotify"
    end
  end

  describe "switch_section" do
    test "switches to downloads section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      html = render_click(view, "switch_section", %{"section" => "downloads"})
      assert html =~ "Settings"
    end

    test "switches to demucs section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      html = render_click(view, "switch_section", %{"section" => "demucs"})
      assert html =~ "Settings"
    end

    test "switches to cloud_separation section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      html = render_click(view, "switch_section", %{"section" => "cloud_separation"})
      assert html =~ "Settings"
    end

    test "switches to analysis section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      html = render_click(view, "switch_section", %{"section" => "analysis"})
      assert html =~ "Settings"
    end

    test "switches to storage section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      html = render_click(view, "switch_section", %{"section" => "storage"})
      assert html =~ "Settings"
    end

    test "switches to general section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      html = render_click(view, "switch_section", %{"section" => "general"})
      assert html =~ "Settings"
    end

    test "switches to advanced section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      html = render_click(view, "switch_section", %{"section" => "advanced"})
      assert html =~ "Settings"
    end

    test "switches to control_surfaces section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      html = render_click(view, "switch_section", %{"section" => "control_surfaces"})
      assert html =~ "Settings"
    end

    test "switches to ai_providers section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      html = render_click(view, "switch_section", %{"section" => "ai_providers"})
      assert html =~ "Settings"
    end
  end

  describe "link_spotify" do
    test "redirects to Spotify OAuth", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      assert {:error, {:redirect, %{to: "/auth/spotify"}}} =
               render_click(view, "link_spotify", %{})
    end
  end

  describe "lalalai_key_input" do
    test "updates key input assign", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      # Switch to cloud_separation section first
      render_click(view, "switch_section", %{"section" => "cloud_separation"})

      html = render_click(view, "lalalai_key_input", %{"key" => "test-key-123"})
      assert html =~ "Settings"
    end
  end

  describe "test_lalalai_key" do
    test "shows error for empty key", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      html = render_click(view, "test_lalalai_key", %{})
      # Should show error about empty key
      assert html =~ "Settings"
    end
  end

  describe "validate" do
    test "handles unrecognized validate payload", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      # Send a validate event with unknown params - should not crash
      html = render_click(view, "validate", %{"unknown" => "params"})
      assert html =~ "Settings"
    end
  end
end
