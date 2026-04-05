defmodule SoundForgeWeb.SettingsLiveExtendedTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SoundForge.AccountsFixtures

  setup :register_and_log_in_user

  describe "cloud separation section" do
    test "switches to cloud separation section and shows lalal.ai config", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> element("button", "Cloud Separation")
        |> render_click()

      assert html =~ "Cloud Stem Separation"
      assert html =~ "lalal.ai"
    end

    test "shows API key input when not configured", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> element("button", "Cloud Separation")
        |> render_click()

      assert html =~ "API key"
    end
  end

  describe "youtube section" do
    test "switches to youtube section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> element("button", "YouTube")
        |> render_click()

      assert html =~ "YouTube"
      assert html =~ "yt-dlp"
    end

    test "shows search depth setting", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> element("button", "YouTube")
        |> render_click()

      assert html =~ "Search Depth"
    end
  end

  describe "storage section" do
    test "switches to storage section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> element("button", "Storage")
        |> render_click()

      assert html =~ "Storage Settings"
    end
  end

  describe "advanced section" do
    test "switches to advanced section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> element("button", "Advanced")
        |> render_click()

      assert html =~ "Advanced Settings"
    end
  end

  describe "ai providers section" do
    test "switches to AI providers section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> element("button", "AI Providers")
        |> render_click()

      assert html =~ "AI Providers"
    end
  end

  describe "demucs settings form" do
    test "validates demucs model selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("button", "Demucs")
      |> render_click()

      html =
        view
        |> form("form", user_settings: %{demucs_model: "mdx_extra"})
        |> render_change()

      assert html =~ "Demucs Settings"
    end
  end

  describe "download settings form" do
    test "validates audio format change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("button", "Downloads")
      |> render_click()

      html =
        view
        |> form("form", user_settings: %{audio_format: "flac"})
        |> render_change()

      assert html =~ "Download"
    end

    test "saves audio format", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("button", "Downloads")
      |> render_click()

      view
      |> form("form", user_settings: %{audio_format: "flac"})
      |> render_submit()

      assert SoundForge.Settings.get(user.id, :audio_format) == "flac"
    end
  end

  describe "form dirty tracking" do
    test "form validate event triggers without error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("button", "Downloads")
      |> render_click()

      html =
        view
        |> form("form", user_settings: %{download_quality: "192k"})
        |> render_change()

      # Should render without crashing
      assert html =~ "Download"
    end
  end

  describe "spotify section" do
    test "shows link spotify button when not linked", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")
      assert html =~ "Spotify"
    end
  end
end
