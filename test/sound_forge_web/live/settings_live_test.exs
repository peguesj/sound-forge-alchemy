defmodule SoundForgeWeb.SettingsLiveTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "mount" do
    test "renders settings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")
      assert html =~ "Spotify Integration"
      assert html =~ "Settings"
    end

    test "shows tool status", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")
      assert html =~ "SpotDL"
      assert html =~ "FFmpeg"
    end
  end

  describe "section switching" do
    test "switches to downloads section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> element("button", "Downloads")
        |> render_click()

      assert html =~ "Download Settings"
      assert html =~ "Download Quality"
    end

    test "switches to demucs section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> element("button", "Demucs")
        |> render_click()

      assert html =~ "Demucs Settings"
      assert html =~ "Model"
    end

    test "switches to analysis section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> element("button", "Analysis")
        |> render_click()

      assert html =~ "Analysis Settings"
    end

    test "switches to general section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> element("button", "General")
        |> render_click()

      assert html =~ "General Settings"
      assert html =~ "Tracks Per Page"
    end
  end

  describe "save settings" do
    test "saves download quality", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("button", "Downloads")
      |> render_click()

      view
      |> form("form", user_settings: %{download_quality: "256k"})
      |> render_submit()

      assert SoundForge.Settings.get(user.id, :download_quality) == "256k"
    end

    test "saves demucs model", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("button", "Demucs")
      |> render_click()

      view
      |> form("form", user_settings: %{demucs_model: "htdemucs_ft"})
      |> render_submit()

      assert SoundForge.Settings.get(user.id, :demucs_model) == "htdemucs_ft"
    end
  end

  describe "reset section" do
    test "resets section to defaults", %{conn: conn, user: user} do
      SoundForge.Settings.save_user_settings(user.id, %{demucs_model: "mdx_extra"})
      assert SoundForge.Settings.get(user.id, :demucs_model) == "mdx_extra"

      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("button", "Demucs")
      |> render_click()

      view
      |> element(~s{button[phx-click="reset_section"][phx-value-section="demucs"]})
      |> render_click()

      assert SoundForge.Settings.get(user.id, :demucs_model) == "htdemucs"
    end
  end
end
