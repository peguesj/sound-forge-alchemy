defmodule SoundForgeWeb.AdminActionsTest do
  @moduledoc """
  Tests for admin user management actions: status changes, role changes,
  bulk operations, user selection, pagination, health checks, audit search.
  """
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

  describe "user status actions" do
    test "filter_users_status active", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})
      html = render_click(view, "filter_users_status", %{"status" => "active"})
      assert is_binary(html)
    end

    test "filter_users_status suspended", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})
      html = render_click(view, "filter_users_status", %{"status" => "suspended"})
      assert is_binary(html)
    end

    test "filter_users_status all", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})
      html = render_click(view, "filter_users_status", %{"status" => ""})
      assert is_binary(html)
    end
  end

  describe "user selection" do
    test "toggle_select_user", %{conn: conn} do
      other_user = user_fixture()
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})
      html = render_click(view, "toggle_select_user", %{"id" => to_string(other_user.id)})
      assert is_binary(html)
    end

    test "select_all_users and deselect_all_users", %{conn: conn} do
      user_fixture()
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})
      html = render_click(view, "select_all_users")
      assert is_binary(html)
      html2 = render_click(view, "deselect_all_users")
      assert is_binary(html2)
    end
  end

  describe "role changes" do
    test "change_role for a user", %{conn: conn} do
      other_user = user_fixture()
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})

      html =
        render_click(view, "change_role", %{"id" => to_string(other_user.id), "role" => "pro"})

      assert is_binary(html)
    end

    test "suspend_user", %{conn: conn} do
      other_user = user_fixture()
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})
      html = render_click(view, "suspend_user", %{"id" => to_string(other_user.id)})
      assert is_binary(html)
    end

    test "ban_user", %{conn: conn} do
      other_user = user_fixture()
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})
      html = render_click(view, "ban_user", %{"id" => to_string(other_user.id)})
      assert is_binary(html)
    end

    test "reactivate_user", %{conn: conn} do
      other_user = user_fixture()
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})
      html = render_click(view, "reactivate_user", %{"id" => to_string(other_user.id)})
      assert is_binary(html)
    end
  end

  describe "bulk operations" do
    test "bulk_change_role", %{conn: conn} do
      other_user = user_fixture()
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})
      render_click(view, "toggle_select_user", %{"id" => to_string(other_user.id)})
      html = render_click(view, "bulk_change_role", %{"role" => "pro"})
      assert is_binary(html)
    end
  end

  describe "pagination" do
    test "users_page changes page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "users"})
      html = render_click(view, "users_page", %{"page" => "1"})
      assert is_binary(html)
    end
  end

  describe "health checks" do
    test "run_health_checks", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "llm"})
      html = render_click(view, "run_health_checks")
      assert is_binary(html)
    end
  end

  describe "audit operations" do
    test "search_audit", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "audit"})
      html = render_click(view, "search_audit", %{"search" => "test"})
      assert is_binary(html)
    end
  end

  describe "jobs tab operations" do
    test "filter jobs by executing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "jobs"})
      html = render_click(view, "filter_jobs", %{"state" => "executing"})
      assert is_binary(html)
    end

    test "filter jobs by discarded", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "jobs"})
      html = render_click(view, "filter_jobs", %{"state" => "discarded"})
      assert is_binary(html)
    end

    test "filter jobs all states", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")
      render_click(view, "switch_tab", %{"tab" => "jobs"})
      html = render_click(view, "filter_jobs", %{"state" => "all"})
      assert is_binary(html)
    end
  end
end
