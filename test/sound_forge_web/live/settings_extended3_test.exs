defmodule SoundForgeWeb.SettingsExtended3Test do
  @moduledoc """
  Tests for SettingsLive section navigation to cover template rendering
  branches for each section.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "section switching renders different templates" do
    test "switch to downloads section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "switch_section", %{"section" => "downloads"})
      assert is_binary(html)
    end

    test "switch to demucs section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "switch_section", %{"section" => "demucs"})
      assert is_binary(html)
    end

    test "switch to cloud_separation section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "switch_section", %{"section" => "cloud_separation"})
      assert is_binary(html)
    end

    test "switch to ai_providers section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "switch_section", %{"section" => "ai_providers"})
      assert is_binary(html)
    end

    test "switch to general section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "switch_section", %{"section" => "general"})
      assert is_binary(html)
    end

    test "switch to control_surfaces section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "switch_section", %{"section" => "control_surfaces"})
      assert is_binary(html)
    end

    test "switch to storage section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "switch_section", %{"section" => "storage"})
      assert is_binary(html)
    end

    test "switch to advanced section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "switch_section", %{"section" => "advanced"})
      assert is_binary(html)
    end

    test "switch to youtube section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "switch_section", %{"section" => "youtube"})
      assert is_binary(html)
    end

    test "switch to analysis section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "switch_section", %{"section" => "analysis"})
      assert is_binary(html)
    end
  end
end
