defmodule Mix.Tasks.PromoteAdminTest do
  use SoundForge.DataCase

  import SoundForge.AccountsFixtures

  describe "run/1" do
    test "promotes a user to admin by email" do
      user = user_fixture()
      assert user.role == :user

      Mix.Tasks.PromoteAdmin.run([user.email])

      updated = SoundForge.Repo.reload!(user)
      assert updated.role == :admin
    end

    test "reports when user is already admin" do
      user = user_fixture()
      SoundForge.Repo.update!(Ecto.Changeset.change(user, role: :admin))

      # Should not crash, just inform
      Mix.Tasks.PromoteAdmin.run([user.email])

      updated = SoundForge.Repo.reload!(user)
      assert updated.role == :admin
    end

    test "reports error for unknown email" do
      # Should not crash
      Mix.Tasks.PromoteAdmin.run(["nonexistent@example.com"])
    end

    test "reports error for missing arguments" do
      # Should not crash
      Mix.Tasks.PromoteAdmin.run([])
    end
  end
end
