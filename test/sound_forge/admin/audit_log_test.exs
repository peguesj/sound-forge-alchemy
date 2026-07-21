defmodule SoundForge.Admin.AuditLogTest do
  use ExUnit.Case, async: true

  alias SoundForge.Admin.AuditLog

  @valid_attrs %{action: "create", resource_type: "user"}

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      cs = AuditLog.changeset(%AuditLog{}, @valid_attrs)
      assert cs.valid?
    end

    test "requires action" do
      cs = AuditLog.changeset(%AuditLog{}, Map.delete(@valid_attrs, :action))
      refute cs.valid?
    end

    test "requires resource_type" do
      cs = AuditLog.changeset(%AuditLog{}, Map.delete(@valid_attrs, :resource_type))
      refute cs.valid?
    end

    test "validates all action types" do
      valid_actions =
        ~w(create update delete suspend ban reactivate role_change bulk_role_change config_update feature_flag_toggle login logout)

      for action <- valid_actions do
        cs = AuditLog.changeset(%AuditLog{}, %{@valid_attrs | action: action})
        assert cs.valid?, "Expected action '#{action}' to be valid"
      end
    end

    test "rejects invalid action" do
      cs = AuditLog.changeset(%AuditLog{}, %{@valid_attrs | action: "hack"})
      refute cs.valid?
    end

    test "optional fields" do
      cs =
        AuditLog.changeset(
          %AuditLog{},
          Map.merge(@valid_attrs, %{
            resource_id: "123",
            changes: %{"role" => "admin"},
            ip_address: "192.168.1.1",
            actor_id: 42
          })
        )

      assert cs.valid?
    end

    test "changes defaults to empty map" do
      al = %AuditLog{}
      assert al.changes == %{}
    end
  end
end
