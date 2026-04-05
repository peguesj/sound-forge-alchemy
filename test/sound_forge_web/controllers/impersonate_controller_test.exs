defmodule SoundForgeWeb.ImpersonateControllerTest do
  @moduledoc "Tests for ImpersonateController (dev-only, routes not available in test env)."
  use SoundForgeWeb.ConnCase

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.ImpersonateController)
    end

    test "create/2 is exported" do
      assert {:create, 2} in SoundForgeWeb.ImpersonateController.__info__(:functions)
    end

    test "delete/2 is exported" do
      assert {:delete, 2} in SoundForgeWeb.ImpersonateController.__info__(:functions)
    end
  end
end
