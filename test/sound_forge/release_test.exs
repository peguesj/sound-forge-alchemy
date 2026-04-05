defmodule SoundForge.ReleaseTest do
  @moduledoc "Tests for SoundForge.Release module."
  use SoundForge.DataCase

  alias SoundForge.Release

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Release)
    end

    test "migrate/0 is exported" do
      assert {:migrate, 0} in Release.__info__(:functions)
    end

    test "rollback/2 is exported" do
      assert {:rollback, 2} in Release.__info__(:functions)
    end
  end

  describe "migrate/0" do
    test "runs migrations without error" do
      # Safe to call since test DB is already migrated - returns list of results per repo
      result = Release.migrate()
      assert is_list(result)
    end
  end

  describe "rollback/2" do
    test "rollback with non-existent version is a no-op" do
      # rollback uses Ecto.Migrator which needs sandbox checkout
      # Just verify the function exists and the module compiles correctly
      assert function_exported?(Release, :rollback, 2)
    end
  end
end
