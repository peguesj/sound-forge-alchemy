defmodule SoundForgeWeb.SettingsSectionsTest do
  @moduledoc "Tests for SettingsLive section switching and rendering."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "section switching" do
    test "renders default section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")
      assert is_binary(html)
    end

    test "switches to downloads section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "switch_section", %{"section" => "downloads"})
      assert is_binary(html)
    end

    test "switches to youtube section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "switch_section", %{"section" => "youtube"})
      assert is_binary(html)
    end

    test "switches to demucs section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "switch_section", %{"section" => "demucs"})
      assert is_binary(html)
    end

    test "switches to cloud_separation section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "switch_section", %{"section" => "cloud_separation"})
      assert is_binary(html)
    end

    test "switches to analysis section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "switch_section", %{"section" => "analysis"})
      assert is_binary(html)
    end

    test "switches to storage section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "switch_section", %{"section" => "storage"})
      assert is_binary(html)
    end

    test "switches to control_surfaces section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "switch_section", %{"section" => "control_surfaces"})
      assert is_binary(html)
    end

    test "switches to general section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "switch_section", %{"section" => "general"})
      assert is_binary(html)
    end

    test "switches to advanced section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "switch_section", %{"section" => "advanced"})
      assert is_binary(html)
    end

    test "switches to ai_providers section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "switch_section", %{"section" => "ai_providers"})
      assert is_binary(html)
    end

    test "switches to spotify section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "switch_section", %{"section" => "spotify"})
      assert is_binary(html)
    end
  end

  describe "settings form events" do
    test "validate event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_change(view, "validate", %{"user_settings" => %{"download_format" => "mp3"}})
      assert is_binary(html)
    end

    test "save event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_submit(view, "save", %{"user_settings" => %{"download_format" => "mp3"}})
      assert is_binary(html)
    end

    test "reset_section event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "reset_section", %{"section" => "spotify"})
      assert is_binary(html)
    end
  end

  describe "lalalai key events" do
    test "lalalai_key_input event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      render_click(view, "switch_section", %{"section" => "cloud_separation"})
      html = render_click(view, "lalalai_key_input", %{"key" => "test-key-123"})
      assert is_binary(html)
    end

    test "save_lalalai_key event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      render_click(view, "switch_section", %{"section" => "cloud_separation"})
      html = render_click(view, "save_lalalai_key", %{})
      assert is_binary(html)
    end

    test "remove_lalalai_key event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      render_click(view, "switch_section", %{"section" => "cloud_separation"})
      html = render_click(view, "remove_lalalai_key", %{})
      assert is_binary(html)
    end
  end

  describe "provider events" do
    test "show_add_provider event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "show_add_provider", %{})
      assert is_binary(html)
    end

    test "cancel_provider_form event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "cancel_provider_form", %{})
      assert is_binary(html)
    end
  end
end
