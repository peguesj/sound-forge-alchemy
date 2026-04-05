defmodule SoundForge.AdminTest do
  use SoundForge.DataCase

  alias SoundForge.Admin

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  describe "system_stats/0" do
    test "returns stats map" do
      stats = Admin.system_stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :user_count)
      assert Map.has_key?(stats, :track_count)
    end
  end

  describe "list_users/1" do
    setup do
      user1 = user_fixture()
      user2 = user_fixture()
      %{users: [user1, user2]}
    end

    test "returns paginated users" do
      result = Admin.list_users([])
      assert is_map(result)
      assert is_list(result.users)
      assert result.total >= 2
    end

    test "supports search filter" do
      user = user_fixture()
      result = Admin.list_users(search: user.email)
      assert length(result.users) >= 1
      assert Enum.any?(result.users, &(&1.email == user.email))
    end

    test "supports role filter" do
      result = Admin.list_users(role: :user)
      assert is_list(result.users)
    end

    test "supports pagination" do
      result = Admin.list_users(page: 1, per_page: 1)
      assert length(result.users) <= 1
    end
  end

  describe "log_action/5" do
    test "creates audit log entry" do
      user = user_fixture()
      assert {:ok, log} = Admin.log_action(user.id, "create", "track", Ecto.UUID.generate(), %{title: "New Track"})
      assert log.action == "create"
      assert log.resource_type == "track"
    end
  end

  describe "list_audit_logs/1" do
    test "returns paginated audit logs" do
      user = user_fixture()
      Admin.log_action(user.id, "create", "track", "1", %{})
      Admin.log_action(user.id, "update", "track", "1", %{})

      result = Admin.list_audit_logs([])
      assert is_list(result)
      assert length(result) >= 2
    end
  end

  describe "user_registrations_by_day/1" do
    test "returns daily registration counts" do
      user_fixture()
      result = Admin.user_registrations_by_day(7)
      assert is_list(result)
    end
  end

  describe "tracks_by_day/1" do
    test "returns daily track counts" do
      user = user_fixture()
      track_fixture(%{user_id: user.id})
      result = Admin.tracks_by_day(7)
      assert is_list(result)
    end
  end

  describe "pipeline_throughput/0" do
    test "returns throughput data" do
      result = Admin.pipeline_throughput()
      assert is_map(result)
    end
  end

  describe "role management" do
    setup do
      user = user_fixture()
      admin = user_fixture()
      %{user: user, admin: admin}
    end

    test "update_user_role/3 changes role", %{user: user, admin: admin} do
      assert {:ok, updated} = Admin.update_user_role(user.id, :pro, admin.id)
      assert updated.role == :pro
    end

    test "suspend_user/2 sets status to suspended", %{user: user, admin: admin} do
      assert {:ok, suspended} = Admin.suspend_user(user.id, admin.id)
      assert suspended.status == :suspended
    end

    test "ban_user/2 sets status to banned", %{user: user, admin: admin} do
      assert {:ok, banned} = Admin.ban_user(user.id, admin.id)
      assert banned.status == :banned
    end

    test "reactivate_user/2 sets status to active", %{user: user, admin: admin} do
      Admin.suspend_user(user.id, admin.id)
      assert {:ok, reactivated} = Admin.reactivate_user(user.id, admin.id)
      assert reactivated.status == :active
    end
  end
end
