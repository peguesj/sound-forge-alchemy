defmodule SoundForgeWeb.AdminLiveExtendedTest do
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.AccountsFixtures
  import Ecto.Query

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

  describe "users tab - search" do
    test "renders search input on users tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "users"})

      assert html =~ "Search by email"
      assert html =~ "search"
    end

    test "search_users event updates user list", %{conn: conn} do
      # Create an additional user to search for
      other_user = user_fixture(%{email: "searchme@example.com"})

      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})

      html = render_click(view, "search_users", %{"search" => "searchme"})

      assert html =~ "searchme@example.com"
    end
  end

  describe "users tab - role filter" do
    test "renders role filter dropdown", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "users"})

      assert html =~ "All Roles"
      assert html =~ "User"
      assert html =~ "Admin"
    end

    test "filter_users_role event filters by role", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})

      html = render_click(view, "filter_users_role", %{"role" => "admin"})

      # Should show only admin users (at least our admin user)
      assert html =~ "Admin"
    end

    test "filter_users_role with empty string shows all roles", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})

      html = render_click(view, "filter_users_role", %{"role" => ""})

      assert html =~ "All Roles"
    end
  end

  describe "jobs tab content" do
    test "renders job filter buttons", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "jobs"})

      assert html =~ "All"
      assert html =~ "Executing"
      assert html =~ "Completed"
      assert html =~ "Discarded"
    end

    test "renders job table headers", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "jobs"})

      assert html =~ "Worker"
      assert html =~ "Queue"
      assert html =~ "State"
    end

    test "filter_jobs event works", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "jobs"})

      html = render_click(view, "filter_jobs", %{"state" => "completed"})

      # Should render without crashing
      assert html =~ "Completed"
    end
  end

  describe "system tab content" do
    test "renders storage info", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "system"})

      assert html =~ "Storage"
      assert html =~ "Oban Queues"
    end

    test "renders role distribution", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "system"})

      assert html =~ "Role Distribution"
    end
  end

  describe "audit tab content" do
    test "renders audit log search", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "audit"})

      assert html =~ "Search audit logs"
      assert html =~ "All Actions"
    end

    test "renders action filter dropdown", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "audit"})

      assert html =~ "Role change"
      assert html =~ "Suspend"
      assert html =~ "Ban"
    end

    test "renders empty audit log message when no logs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "audit"})

      assert html =~ "No audit logs found"
    end

    test "filter_audit_action event works", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "audit"})

      html = render_click(view, "filter_audit_action", %{"action" => "role_change"})

      # Should render without crashing
      assert html =~ "Audit"
    end
  end

  describe "overview tab content" do
    test "renders stat cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin")

      assert html =~ "Total Users"
      assert html =~ "Total Tracks"
      assert html =~ "Active Jobs"
      assert html =~ "Failed Jobs"
    end

    test "renders users by role card", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin")

      assert html =~ "Users by Role"
    end

    test "renders users by status card", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin")

      assert html =~ "Users by Status"
    end
  end

  describe "analytics tab" do
    test "renders analytics charts", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "analytics"})

      assert html =~ "User Registrations"
      assert html =~ "Track Imports"
      assert html =~ "Pipeline Throughput"
    end
  end

  describe "llm tab" do
    test "renders LLM provider stats", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "llm"})

      assert html =~ "Total Providers"
      assert html =~ "Enabled Providers"
      assert html =~ "Healthy Providers"
    end

    test "renders health check button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html = render_click(view, "switch_tab", %{"tab" => "llm"})

      assert html =~ "Run Health Checks"
    end
  end
end
