defmodule SoundForge.Accounts.UserTest do
  use ExUnit.Case, async: true

  alias SoundForge.Accounts.User

  describe "struct defaults" do
    test "role defaults to :user" do
      user = %User{}
      assert user.role == :user
    end

    test "status defaults to :active" do
      user = %User{}
      assert user.status == :active
    end
  end

  describe "email_changeset/3" do
    test "valid email produces valid changeset" do
      changeset = User.email_changeset(%User{}, %{email: "new@example.com"}, validate_unique: false)
      assert changeset.valid?
    end

    test "requires email" do
      changeset = User.email_changeset(%User{}, %{}, validate_unique: false)
      refute changeset.valid?
    end

    test "validates email format" do
      changeset = User.email_changeset(%User{}, %{email: "notanemail"}, validate_unique: false)
      refute changeset.valid?
    end

    test "rejects email with spaces" do
      changeset = User.email_changeset(%User{}, %{email: "has space@example.com"}, validate_unique: false)
      refute changeset.valid?
    end

    test "validates email max length" do
      long_email = String.duplicate("a", 150) <> "@example.com"
      changeset = User.email_changeset(%User{}, %{email: long_email}, validate_unique: false)
      refute changeset.valid?
    end

    test "accepts valid email formats" do
      for email <- ["user@example.com", "user+tag@domain.co", "a@b.c"] do
        changeset = User.email_changeset(%User{}, %{email: email}, validate_unique: false)
        assert changeset.valid?, "Expected #{email} to be valid"
      end
    end
  end
end
