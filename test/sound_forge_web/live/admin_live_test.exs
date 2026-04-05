defmodule SoundForgeWeb.AdminLiveTest do
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.AccountsFixtures
  import Ecto.Query

  describe "admin access" do
    test "redirects non-admin users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin")
    end

    test "redirects unauthenticated users to login" do
      conn = build_conn()
      {:error, {:redirect, %{to: to}}} = live(conn, "/admin")
      assert to == "/users/log-in"
    end
  end

  describe "admin dashboard" do
    setup do
      admin = user_fixture()
      # Promote to admin role
      SoundForge.Repo.update_all(
        from(u in SoundForge.Accounts.User, where: u.id == ^admin.id),
        set: [role: :admin]
      )
      admin = SoundForge.Accounts.get_user!(admin.id)
      conn = build_conn() |> log_in_user(admin)

      %{conn: conn, admin: admin}
    end

    test "renders admin dashboard for admin user", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin")
      assert html =~ "Admin Dashboard"
    end

    test "shows overview tab by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin")
      assert html =~ "Total Users"
    end

    test "switches to users tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      html = render_click(view, "switch_tab", %{"tab" => "users"})
      assert html =~ "Search by email"
      assert html =~ "All Roles"
    end

    test "switches to jobs tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      html = render_click(view, "switch_tab", %{"tab" => "jobs"})
      assert html =~ "Jobs"
    end

    test "switches to system tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      html = render_click(view, "switch_tab", %{"tab" => "system"})
      assert html =~ "System"
    end

    test "switches to audit tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      html = render_click(view, "switch_tab", %{"tab" => "audit"})
      assert html =~ "Audit"
    end
  end
end
