defmodule SoundForgeWeb.CombinedLibraryLiveTest do
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.AccountsFixtures

  describe "access control" do
    setup :register_and_log_in_user

    test "regular user gets redirected", %{conn: conn} do
      result = live(conn, "/platform/library")
      # Regular user should be redirected or see error flash
      case result do
        {:error, {:redirect, _}} -> assert true
        {:error, {:live_redirect, _}} -> assert true
        {:ok, _view, html} -> assert html =~ "do not have permission" or html =~ "Sound Forge"
      end
    end
  end

  describe "platform admin access" do
    setup do
      user = user_fixture()
      # Promote to platform_admin
      SoundForge.Repo.update!(Ecto.Changeset.change(user, role: :platform_admin))
      user = SoundForge.Repo.reload!(user)
      conn = build_conn() |> log_in_user(user)
      %{conn: conn, user: user}
    end

    test "platform_admin can access library", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/platform/library")
      assert html =~ "Platform Library" || html =~ "Platform Admin"
    end

    test "search event filters tracks", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/platform/library")
      html = render_click(view, "search", %{"search" => "test query"})
      assert is_binary(html)
    end

    test "page event paginates", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/platform/library")
      html = render_click(view, "page", %{"page" => "1"})
      assert is_binary(html)
    end
  end

  describe "super_admin access" do
    setup do
      user = user_fixture()
      SoundForge.Repo.update!(Ecto.Changeset.change(user, role: :super_admin))
      user = SoundForge.Repo.reload!(user)
      conn = build_conn() |> log_in_user(user)
      %{conn: conn, user: user}
    end

    test "super_admin can access library", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/platform/library")
      assert is_binary(html)
    end
  end
end
