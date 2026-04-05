defmodule SoundForge.Accounts.ScopeExpandedTest do
  use ExUnit.Case, async: true

  alias SoundForge.Accounts.Scope
  alias SoundForge.Accounts.User

  describe "for_user/1 - role mapping" do
    test "sets admin? true for admin role" do
      user = %User{id: 1, email: "admin@test.com", role: :admin}
      scope = Scope.for_user(user)
      assert scope.admin?
      refute scope.platform_admin?
    end

    test "sets admin? true for super_admin" do
      user = %User{id: 1, email: "super@test.com", role: :super_admin}
      scope = Scope.for_user(user)
      assert scope.admin?
      assert scope.platform_admin?
    end

    test "sets platform_admin? true for platform_admin role" do
      user = %User{id: 1, email: "pa@test.com", role: :platform_admin}
      scope = Scope.for_user(user)
      refute scope.admin?
      assert scope.platform_admin?
    end

    test "regular user has no admin flags" do
      user = %User{id: 1, email: "user@test.com", role: :user}
      scope = Scope.for_user(user)
      refute scope.admin?
      refute scope.platform_admin?
      assert scope.role == :user
    end

    test "pro user has no admin flags" do
      user = %User{id: 1, email: "pro@test.com", role: :pro}
      scope = Scope.for_user(user)
      refute scope.admin?
      refute scope.platform_admin?
    end
  end

  describe "has_role?/2" do
    test "user role meets user minimum" do
      scope = Scope.for_user(%User{id: 1, email: "u@t.com", role: :user})
      assert Scope.has_role?(scope, :user)
    end

    test "admin meets pro minimum" do
      scope = Scope.for_user(%User{id: 1, email: "a@t.com", role: :admin})
      assert Scope.has_role?(scope, :pro)
    end

    test "user does not meet admin minimum" do
      scope = Scope.for_user(%User{id: 1, email: "u@t.com", role: :user})
      refute Scope.has_role?(scope, :admin)
    end

    test "nil scope always returns false" do
      refute Scope.has_role?(nil, :user)
    end
  end

  describe "can_manage_users?/1" do
    test "admin can manage users" do
      scope = Scope.for_user(%User{id: 1, email: "a@t.com", role: :admin})
      assert Scope.can_manage_users?(scope)
    end

    test "pro cannot manage users" do
      scope = Scope.for_user(%User{id: 1, email: "p@t.com", role: :pro})
      refute Scope.can_manage_users?(scope)
    end

    test "nil cannot manage users" do
      refute Scope.can_manage_users?(nil)
    end
  end

  describe "can_configure_system?/1" do
    test "only super_admin can configure system" do
      super = Scope.for_user(%User{id: 1, email: "s@t.com", role: :super_admin})
      assert Scope.can_configure_system?(super)

      admin = Scope.for_user(%User{id: 1, email: "a@t.com", role: :admin})
      refute Scope.can_configure_system?(admin)
    end
  end

  describe "can_use_feature?/2" do
    test "pro can use stem_separation" do
      scope = Scope.for_user(%User{id: 1, email: "p@t.com", role: :pro})
      assert Scope.can_use_feature?(scope, :stem_separation)
    end

    test "regular user cannot use stem_separation" do
      scope = Scope.for_user(%User{id: 1, email: "u@t.com", role: :user})
      refute Scope.can_use_feature?(scope, :stem_separation)
    end

    test "enterprise can use lalalai_cloud" do
      scope = Scope.for_user(%User{id: 1, email: "e@t.com", role: :enterprise})
      assert Scope.can_use_feature?(scope, :lalalai_cloud)
    end

    test "pro cannot use lalalai_cloud" do
      scope = Scope.for_user(%User{id: 1, email: "p@t.com", role: :pro})
      refute Scope.can_use_feature?(scope, :lalalai_cloud)
    end

    test "admin can use admin_dashboard" do
      scope = Scope.for_user(%User{id: 1, email: "a@t.com", role: :admin})
      assert Scope.can_use_feature?(scope, :admin_dashboard)
    end

    test "platform_admin can use platform_library" do
      scope = Scope.for_user(%User{id: 1, email: "pa@t.com", role: :platform_admin})
      assert Scope.can_use_feature?(scope, :platform_library)
    end

    test "only super_admin can use feature_flags" do
      super = Scope.for_user(%User{id: 1, email: "s@t.com", role: :super_admin})
      assert Scope.can_use_feature?(super, :feature_flags)

      admin = Scope.for_user(%User{id: 1, email: "a@t.com", role: :admin})
      refute Scope.can_use_feature?(admin, :feature_flags)
    end

    test "unknown features are allowed for all" do
      scope = Scope.for_user(%User{id: 1, email: "u@t.com", role: :user})
      assert Scope.can_use_feature?(scope, :some_unknown_feature)
    end

    test "nil scope cannot use any feature" do
      refute Scope.can_use_feature?(nil, :stem_separation)
    end
  end
end
