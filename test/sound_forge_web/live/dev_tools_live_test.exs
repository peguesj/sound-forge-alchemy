defmodule SoundForgeWeb.DevToolsLiveTest do
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.AccountsFixtures
  import Ecto.Query

  describe "authentication" do
    test "redirects unauthenticated users to login" do
      conn = build_conn()
      {:error, {:redirect, %{to: to}}} = live(conn, "/admin/dev-tools")
      assert to == "/users/log-in"
    end
  end

  describe "access control for non-admin users" do
    test "redirects regular users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/dev-tools")
    end
  end

  describe "dev tools for admin users" do
    setup do
      admin = user_fixture()

      SoundForge.Repo.update_all(
        from(u in SoundForge.Accounts.User, where: u.id == ^admin.id),
        set: [role: :admin]
      )

      admin = SoundForge.Accounts.get_user!(admin.id)
      conn = build_conn() |> log_in_user(admin)

      %{conn: conn, admin: admin}
    end

    test "renders dev tools page for admin user", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/dev-tools")
      assert html =~ "Dev Tools"
    end

    test "shows system inspection panel subtitle", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/dev-tools")
      assert html =~ "System inspection panel"
    end

    test "shows seed_users tab by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/dev-tools")
      assert html =~ "seed_users" or html =~ "Seed"
    end

    test "switches to env_vars tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/dev-tools")

      html = render_click(view, "switch_tab", %{"tab" => "env_vars"})
      assert html =~ "Dev Tools"
    end

    test "switches to system_info tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/dev-tools")

      html = render_click(view, "switch_tab", %{"tab" => "system_info"})
      assert html =~ "Dev Tools"
    end

    test "switches to app_config tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/dev-tools")

      html = render_click(view, "switch_tab", %{"tab" => "app_config"})
      assert html =~ "Dev Tools"
    end
  end
end
