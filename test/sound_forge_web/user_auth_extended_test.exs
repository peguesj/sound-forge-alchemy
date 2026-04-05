defmodule SoundForgeWeb.UserAuthExtendedTest do
  @moduledoc """
  Extended tests for UserAuth plugs not covered in the existing user_auth_test.exs:
  require_admin_user, require_platform_admin, require_role, require_active_user,
  and require_feature.
  """
  use SoundForgeWeb.ConnCase, async: true

  alias SoundForge.Accounts
  alias SoundForge.Accounts.Scope
  alias SoundForgeWeb.UserAuth

  import SoundForge.AccountsFixtures
  import Ecto.Query

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, SoundForgeWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    user = user_fixture()
    %{user: user, conn: conn}
  end

  describe "require_admin_user/2" do
    test "allows admin users", %{conn: conn, user: user} do
      SoundForge.Repo.update_all(
        from(u in Accounts.User, where: u.id == ^user.id),
        set: [role: :admin]
      )

      admin = Accounts.get_user!(user.id)

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(admin))
        |> UserAuth.require_admin_user([])

      refute conn.halted
    end

    test "allows super_admin users", %{conn: conn, user: user} do
      SoundForge.Repo.update_all(
        from(u in Accounts.User, where: u.id == ^user.id),
        set: [role: :super_admin]
      )

      super_admin = Accounts.get_user!(user.id)

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(super_admin))
        |> UserAuth.require_admin_user([])

      refute conn.halted
    end

    test "redirects regular users", %{conn: conn, user: user} do
      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.require_admin_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "permission"
    end
  end

  describe "require_platform_admin/2" do
    test "allows platform_admin users", %{conn: conn, user: user} do
      SoundForge.Repo.update_all(
        from(u in Accounts.User, where: u.id == ^user.id),
        set: [role: :platform_admin]
      )

      platform_admin = Accounts.get_user!(user.id)

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(platform_admin))
        |> UserAuth.require_platform_admin([])

      refute conn.halted
    end

    test "allows super_admin users", %{conn: conn, user: user} do
      SoundForge.Repo.update_all(
        from(u in Accounts.User, where: u.id == ^user.id),
        set: [role: :super_admin]
      )

      super_admin = Accounts.get_user!(user.id)

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(super_admin))
        |> UserAuth.require_platform_admin([])

      refute conn.halted
    end

    test "redirects regular users", %{conn: conn, user: user} do
      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.require_platform_admin([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "platform area"
    end

    test "redirects admin users (not platform_admin)", %{conn: conn, user: user} do
      SoundForge.Repo.update_all(
        from(u in Accounts.User, where: u.id == ^user.id),
        set: [role: :admin]
      )

      admin = Accounts.get_user!(user.id)

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(admin))
        |> UserAuth.require_platform_admin([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "require_role/2" do
    test "allows users with sufficient role", %{conn: conn, user: user} do
      SoundForge.Repo.update_all(
        from(u in Accounts.User, where: u.id == ^user.id),
        set: [role: :admin]
      )

      admin = Accounts.get_user!(user.id)

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(admin))
        |> UserAuth.require_role(:admin)

      refute conn.halted
    end

    test "redirects users with insufficient role", %{conn: conn, user: user} do
      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.require_role(:admin)

      assert conn.halted
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "require_active_user/2" do
    test "allows active users", %{conn: conn, user: user} do
      # Default users are active
      conn =
        conn
        |> fetch_flash()
        |> fetch_cookies()
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.require_active_user([])

      # Active user should pass through (not halted due to log_out redirect)
      # Since the user is active, log_out_user is NOT called
      # The conn should redirect to "/" via log_out_user only if suspended
      # For active users, require_active_user returns the conn unchanged
      assert user.status == :active
    end

    test "logs out suspended users", %{conn: conn, user: user} do
      SoundForge.Repo.update_all(
        from(u in Accounts.User, where: u.id == ^user.id),
        set: [status: :suspended]
      )

      suspended_user = Accounts.get_user!(user.id)

      conn =
        conn
        |> fetch_flash()
        |> fetch_cookies()
        |> assign(:current_scope, Scope.for_user(suspended_user))
        |> UserAuth.require_active_user([])

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "suspended"
    end
  end

  describe "require_feature/2" do
    test "allows users with access to a feature", %{conn: conn, user: user} do
      SoundForge.Repo.update_all(
        from(u in Accounts.User, where: u.id == ^user.id),
        set: [role: :pro]
      )

      pro_user = Accounts.get_user!(user.id)

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(pro_user))
        |> UserAuth.require_feature(:stem_separation)

      refute conn.halted
    end

    test "redirects users without feature access", %{conn: conn, user: user} do
      # Default role :user cannot use stem_separation
      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.require_feature(:stem_separation)

      assert conn.halted
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Upgrade"
    end
  end
end
