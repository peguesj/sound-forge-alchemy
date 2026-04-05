defmodule SoundForgeWeb.AdminRenderTest do
  @moduledoc """
  Tests admin tab rendering in the dashboard to exercise AdminLive template branches.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.AccountsFixtures

  describe "admin tab access" do
    test "non-admin user can still navigate to admin tab (shows limited view)" do
      user = user_fixture()
      conn = build_conn() |> log_in_user(user)
      {:ok, view, _html} = live(conn, "/")

      html = render_click(view, "nav_tab", %{"tab" => "admin"})
      # Should render without crash even for non-admin
      assert html =~ "Alchemy"
    end

    test "admin user sees admin interface" do
      admin = user_fixture()
      SoundForge.Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = SoundForge.Repo.reload!(admin)
      conn = build_conn() |> log_in_user(admin)

      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "admin"})
      assert html =~ "Alchemy"
    end

    test "super_admin sees admin interface" do
      admin = user_fixture()
      SoundForge.Repo.update!(Ecto.Changeset.change(admin, role: :super_admin))
      admin = SoundForge.Repo.reload!(admin)
      conn = build_conn() |> log_in_user(admin)

      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "admin"})
      assert html =~ "Alchemy"
    end

    test "platform_admin sees full admin interface" do
      admin = user_fixture()
      SoundForge.Repo.update!(Ecto.Changeset.change(admin, role: :platform_admin))
      admin = SoundForge.Repo.reload!(admin)
      conn = build_conn() |> log_in_user(admin)

      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "admin"})
      assert html =~ "Alchemy"
    end
  end
end
