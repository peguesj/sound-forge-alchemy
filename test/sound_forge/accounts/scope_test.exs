defmodule SoundForge.Accounts.ScopeTest do
  use SoundForge.DataCase, async: true

  alias SoundForge.Accounts.Scope
  alias SoundForge.Accounts.User

  describe "for_user/1" do
    test "returns scope struct for a user" do
      user = %User{id: 1, email: "test@example.com"}
      scope = Scope.for_user(user)

      assert %Scope{user: ^user} = scope
    end

    test "returns nil for nil user" do
      assert Scope.for_user(nil) == nil
    end
  end
end
