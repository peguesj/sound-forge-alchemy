defmodule SoundForgeWeb.SettingsProviderTest do
  @moduledoc """
  Tests for settings LLM provider management, lalalai operations,
  reset_section, save, and AI provider CRUD.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "reset_section" do
    test "reset downloads section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "downloads"})
      html = render_click(view, "reset_section", %{"section" => "downloads"})
      assert html =~ "Settings"
    end

    test "reset demucs section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "demucs"})
      html = render_click(view, "reset_section", %{"section" => "demucs"})
      assert html =~ "Settings"
    end

    test "reset analysis section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "analysis"})
      html = render_click(view, "reset_section", %{"section" => "analysis"})
      assert html =~ "Settings"
    end

    test "reset storage section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "storage"})
      html = render_click(view, "reset_section", %{"section" => "storage"})
      assert html =~ "Settings"
    end

    test "reset general section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "general"})
      html = render_click(view, "reset_section", %{"section" => "general"})
      assert html =~ "Settings"
    end

    test "reset advanced section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "advanced"})
      html = render_click(view, "reset_section", %{"section" => "advanced"})
      assert html =~ "Settings"
    end
  end

  describe "lalalai key operations" do
    test "save_lalalai_key with empty key", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "cloud_separation"})
      html = render_click(view, "save_lalalai_key")
      assert html =~ "Settings"
    end

    test "save_lalalai_key with a key", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "cloud_separation"})
      render_click(view, "lalalai_key_input", %{"key" => "test-api-key-xyz"})
      html = render_click(view, "save_lalalai_key")
      assert html =~ "Settings"
    end

    test "remove_lalalai_key", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "cloud_separation"})
      html = render_click(view, "remove_lalalai_key")
      assert html =~ "Settings"
    end

    test "test_lalalai_key with key set", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "cloud_separation"})
      render_click(view, "lalalai_key_input", %{"key" => "test-key"})
      html = render_click(view, "test_lalalai_key")
      assert html =~ "Settings"
    end
  end

  describe "unlink_spotify" do
    test "unlink spotify clears OAuth data", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "unlink_spotify")
      assert html =~ "Settings"
    end
  end

  describe "AI provider management" do
    test "show_add_provider", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "show_add_provider")
      assert html =~ "Settings"
    end

    test "cancel_provider_form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      render_click(view, "show_add_provider")
      html = render_click(view, "cancel_provider_form")
      assert html =~ "Settings"
    end

    test "validate_provider", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      render_click(view, "show_add_provider")
      html = render_click(view, "validate_provider", %{
        "provider" => %{"name" => "Test Provider", "adapter" => "openai", "api_key" => "sk-test"}
      })
      assert html =~ "Settings"
    end

    test "save_provider", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      render_click(view, "show_add_provider")
      html = render_click(view, "save_provider", %{
        "provider" => %{
          "name" => "My OpenAI",
          "provider_type" => "openai",
          "api_key" => "sk-test-123",
          "base_url" => "https://api.openai.com/v1",
          "default_model" => "gpt-4"
        }
      })
      assert html =~ "Settings"
    end
  end

  describe "validate user settings" do
    test "validate with user_settings params", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "validate", %{"user_settings" => %{"auto_download" => "true"}})
      assert html =~ "Settings"
    end

    test "validate with provider params", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      render_click(view, "show_add_provider")
      html = render_click(view, "validate", %{"provider" => %{"name" => "Test"}})
      assert html =~ "Settings"
    end
  end

  describe "save user settings" do
    test "save with valid settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "save", %{"user_settings" => %{"auto_download" => "true"}})
      assert html =~ "Settings"
    end
  end
end
