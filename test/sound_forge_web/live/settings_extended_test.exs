defmodule SoundForgeWeb.SettingsExtendedTest do
  @moduledoc """
  Extended settings tests: edit_provider, delete_provider, toggle_provider,
  test_provider, section switching, youtube/control_surfaces sections.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  alias SoundForge.LLM.Providers

  setup :register_and_log_in_user

  defp create_provider(user) do
    {:ok, provider} =
      Providers.create_provider(user.id, %{
        "name" => "Test Provider",
        "provider_type" => "openai",
        "api_key" => "sk-test-key-123",
        "base_url" => "https://api.openai.com/v1",
        "default_model" => "gpt-4"
      })

    provider
  end

  describe "section switching" do
    test "switch to all available sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")

      for section <-
            ~w(spotify downloads youtube demucs cloud_separation analysis storage general advanced ai_providers) do
        html = render_click(view, "switch_section", %{"section" => section})
        assert html =~ "Settings"
      end
    end

    test "switch to control_surfaces section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "switch_section", %{"section" => "control_surfaces"})
      assert html =~ "Settings"
    end
  end

  describe "edit_provider" do
    test "edit existing provider", %{conn: conn, user: user} do
      provider = create_provider(user)
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "edit_provider", %{"id" => provider.id})
      assert html =~ "Settings"
    end
  end

  describe "delete_provider" do
    test "delete existing provider", %{conn: conn, user: user} do
      provider = create_provider(user)
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "delete_provider", %{"id" => provider.id})
      assert html =~ "Settings"
    end
  end

  describe "toggle_provider" do
    test "toggle provider enabled/disabled", %{conn: conn, user: user} do
      provider = create_provider(user)
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "toggle_provider", %{"id" => provider.id})
      assert html =~ "Settings"
    end
  end

  describe "test_provider" do
    test "test provider connection", %{conn: conn, user: user} do
      provider = create_provider(user)
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      html = render_click(view, "test_provider", %{"id" => provider.id})
      assert html =~ "Settings"
    end
  end

  describe "save_provider with existing provider" do
    test "save_provider in edit mode", %{conn: conn, user: user} do
      provider = create_provider(user)
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "ai_providers"})
      render_click(view, "edit_provider", %{"id" => provider.id})

      html =
        render_click(view, "save_provider", %{
          "provider" => %{
            "name" => "Updated Provider",
            "provider_type" => "openai",
            "api_key" => "sk-updated-key",
            "base_url" => "https://api.openai.com/v1",
            "default_model" => "gpt-4o"
          }
        })

      assert html =~ "Settings"
    end
  end

  describe "validate catch-all" do
    test "validate with empty params does nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "validate", %{})
      assert html =~ "Settings"
    end
  end

  describe "link_spotify" do
    test "link_spotify redirects to OAuth", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      render_click(view, "switch_section", %{"section" => "spotify"})
      assert {:error, {:redirect, %{to: "/auth/spotify"}}} = render_click(view, "link_spotify")
    end
  end
end
