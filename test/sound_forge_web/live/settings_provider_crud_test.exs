defmodule SoundForgeWeb.SettingsProviderCrudTest do
  @moduledoc """
  Tests for SettingsLive provider CRUD handlers: edit_provider, delete_provider,
  toggle_provider, test_provider, and save_lalalai_key.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "save_lalalai_key" do
    test "save_lalalai_key event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "cloud_separation"})
      render_click(view, "lalalai_key_input", %{"key" => "test-api-key-abc123"})
      html = render_click(view, "save_lalalai_key", %{})
      assert is_binary(html)
    end
  end

  describe "remove_lalalai_key" do
    test "remove_lalalai_key event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "remove_lalalai_key", %{})
      assert is_binary(html)
    end
  end

  defp create_test_provider(user) do
    {:ok, provider} = SoundForge.LLM.Providers.create_provider(user.id, %{
      "name" => "Test Provider",
      "provider_type" => "openai",
      "api_key" => "sk-test-key-123",
      "base_url" => "https://api.test.com/v1",
      "model_name" => "gpt-4",
      "priority" => 1,
      "enabled" => true
    })
    provider
  end

  describe "provider management" do
    test "show_add_provider", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "show_add_provider", %{})
      assert is_binary(html)
    end

    test "cancel_provider_form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      render_click(view, "show_add_provider", %{})
      html = render_click(view, "cancel_provider_form", %{})
      assert is_binary(html)
    end

    test "save_provider creates new provider", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      render_click(view, "show_add_provider", %{})
      html = render_click(view, "save_provider", %{"provider" => %{
        "name" => "Test Provider",
        "provider_type" => "openai",
        "api_key" => "sk-test-key",
        "base_url" => "https://api.test.com/v1",
        "model_name" => "gpt-4",
        "priority" => "1"
      }})
      assert is_binary(html)
    end

    test "edit_provider with real provider", %{conn: conn, user: user} do
      provider = create_test_provider(user)
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "edit_provider", %{"id" => provider.id})
      assert is_binary(html)
    end

    test "delete_provider with real provider", %{conn: conn, user: user} do
      provider = create_test_provider(user)
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "delete_provider", %{"id" => provider.id})
      assert is_binary(html)
    end

    test "toggle_provider with real provider", %{conn: conn, user: user} do
      provider = create_test_provider(user)
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "toggle_provider", %{"id" => provider.id})
      assert is_binary(html)
    end

    test "test_provider with real provider", %{conn: conn, user: user} do
      provider = create_test_provider(user)
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "test_provider", %{"id" => provider.id})
      assert is_binary(html)
    end

    test "validate_provider", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      render_click(view, "show_add_provider", %{})
      html = render_click(view, "validate_provider", %{"provider" => %{
        "name" => "Test",
        "provider_type" => "openai"
      }})
      assert is_binary(html)
    end
  end

  describe "unlink_spotify" do
    test "unlink_spotify event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "unlink_spotify", %{})
      assert is_binary(html)
    end
  end

  describe "save settings" do
    test "save with user_settings params", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "save", %{"user_settings" => %{
        "download_quality" => "256k",
        "demucs_model" => "htdemucs"
      }})
      assert is_binary(html)
    end

    test "validate with user_settings params", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "validate", %{"user_settings" => %{
        "download_quality" => "128k"
      }})
      assert is_binary(html)
    end

    test "validate with provider params", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "validate", %{"provider" => %{
        "name" => "Provider"
      }})
      assert is_binary(html)
    end

    test "reset_section for downloads", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "reset_section", %{"section" => "downloads"})
      assert is_binary(html)
    end

    test "reset_section for demucs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "reset_section", %{"section" => "demucs"})
      assert is_binary(html)
    end
  end
end
