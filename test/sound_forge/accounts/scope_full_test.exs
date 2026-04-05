defmodule SoundForge.Accounts.ScopeFullTest do
  @moduledoc """
  Exhaustive coverage for Scope: role_level, can_view_analytics?, can_use_feature? all branches.
  """
  use ExUnit.Case, async: true

  alias SoundForge.Accounts.Scope
  alias SoundForge.Accounts.User

  defp scope(role), do: Scope.for_user(%User{id: 1, email: "t@t.com", role: role})

  describe "role_level/1" do
    test "user = 0" do
      assert Scope.role_level(:user) == 0
    end

    test "pro = 1" do
      assert Scope.role_level(:pro) == 1
    end

    test "enterprise = 2" do
      assert Scope.role_level(:enterprise) == 2
    end

    test "admin = 3" do
      assert Scope.role_level(:admin) == 3
    end

    test "platform_admin = 3" do
      assert Scope.role_level(:platform_admin) == 3
    end

    test "super_admin = 5" do
      assert Scope.role_level(:super_admin) == 5
    end
  end

  describe "for_user/1 enterprise" do
    test "enterprise has no admin flags" do
      s = scope(:enterprise)
      assert s.role == :enterprise
      refute s.admin?
      refute s.platform_admin?
    end
  end

  describe "has_role?/2 all combos" do
    test "enterprise meets enterprise minimum" do
      assert Scope.has_role?(scope(:enterprise), :enterprise)
    end

    test "enterprise does not meet admin" do
      refute Scope.has_role?(scope(:enterprise), :admin)
    end

    test "super_admin meets all" do
      s = scope(:super_admin)
      for role <- [:user, :pro, :enterprise, :admin, :platform_admin, :super_admin] do
        assert Scope.has_role?(s, role), "super_admin should meet #{role}"
      end
    end

    test "platform_admin meets admin" do
      assert Scope.has_role?(scope(:platform_admin), :admin)
    end

    test "pro meets user" do
      assert Scope.has_role?(scope(:pro), :user)
    end

    test "pro does not meet enterprise" do
      refute Scope.has_role?(scope(:pro), :enterprise)
    end
  end

  describe "can_view_analytics?/1" do
    test "admin can view analytics" do
      assert Scope.can_view_analytics?(scope(:admin))
    end

    test "super_admin can view analytics" do
      assert Scope.can_view_analytics?(scope(:super_admin))
    end

    test "enterprise cannot view analytics" do
      refute Scope.can_view_analytics?(scope(:enterprise))
    end

    test "nil cannot view analytics" do
      refute Scope.can_view_analytics?(nil)
    end
  end

  describe "can_manage_users?/1 enterprise" do
    test "enterprise cannot manage users" do
      refute Scope.can_manage_users?(scope(:enterprise))
    end

    test "super_admin can manage users" do
      assert Scope.can_manage_users?(scope(:super_admin))
    end
  end

  describe "can_configure_system?/1 more roles" do
    test "platform_admin cannot configure system" do
      refute Scope.can_configure_system?(scope(:platform_admin))
    end

    test "nil cannot configure system" do
      refute Scope.can_configure_system?(nil)
    end
  end

  describe "can_use_feature?/2 comprehensive" do
    test "osc_touchosc requires enterprise+" do
      refute Scope.can_use_feature?(scope(:pro), :osc_touchosc)
      assert Scope.can_use_feature?(scope(:enterprise), :osc_touchosc)
      assert Scope.can_use_feature?(scope(:admin), :osc_touchosc)
      assert Scope.can_use_feature?(scope(:platform_admin), :osc_touchosc)
      assert Scope.can_use_feature?(scope(:super_admin), :osc_touchosc)
    end

    test "midi_control requires pro+" do
      refute Scope.can_use_feature?(scope(:user), :midi_control)
      assert Scope.can_use_feature?(scope(:pro), :midi_control)
      assert Scope.can_use_feature?(scope(:enterprise), :midi_control)
    end

    test "melodics requires pro+" do
      refute Scope.can_use_feature?(scope(:user), :melodics)
      assert Scope.can_use_feature?(scope(:pro), :melodics)
    end

    test "full_analysis requires pro+" do
      refute Scope.can_use_feature?(scope(:user), :full_analysis)
      assert Scope.can_use_feature?(scope(:pro), :full_analysis)
    end

    test "billing requires super_admin only" do
      refute Scope.can_use_feature?(scope(:admin), :billing)
      refute Scope.can_use_feature?(scope(:platform_admin), :billing)
      assert Scope.can_use_feature?(scope(:super_admin), :billing)
    end

    test "admin_dashboard denied for enterprise" do
      refute Scope.can_use_feature?(scope(:enterprise), :admin_dashboard)
    end

    test "platform_library denied for admin" do
      refute Scope.can_use_feature?(scope(:admin), :platform_library)
    end

    test "stem_separation for all elevated roles" do
      assert Scope.can_use_feature?(scope(:admin), :stem_separation)
      assert Scope.can_use_feature?(scope(:platform_admin), :stem_separation)
      assert Scope.can_use_feature?(scope(:super_admin), :stem_separation)
    end

    test "lalalai_cloud for platform_admin and super_admin" do
      assert Scope.can_use_feature?(scope(:platform_admin), :lalalai_cloud)
      assert Scope.can_use_feature?(scope(:super_admin), :lalalai_cloud)
    end
  end
end
