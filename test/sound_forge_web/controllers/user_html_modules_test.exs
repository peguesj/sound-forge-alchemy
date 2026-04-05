defmodule SoundForgeWeb.UserHTMLModulesTest do
  @moduledoc "Tests for UserRegistrationHTML and UserSettingsHTML module loading."
  use ExUnit.Case, async: true

  describe "UserRegistrationHTML" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.UserRegistrationHTML)
    end

    test "new/1 template function is exported" do
      assert {:new, 1} in SoundForgeWeb.UserRegistrationHTML.__info__(:functions)
    end
  end

  describe "UserSettingsHTML" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.UserSettingsHTML)
    end

    test "edit/1 template function is exported" do
      assert {:edit, 1} in SoundForgeWeb.UserSettingsHTML.__info__(:functions)
    end
  end
end
