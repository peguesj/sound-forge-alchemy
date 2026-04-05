defmodule SoundForgeWeb.HTMLModulesTest do
  use ExUnit.Case, async: true

  describe "UserRegistrationHTML" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.UserRegistrationHTML)
    end
  end

  describe "UserSettingsHTML" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.UserSettingsHTML)
    end
  end

  describe "UserSessionHTML" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.UserSessionHTML)
    end
  end

  describe "ErrorHTML" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.ErrorHTML)
    end
  end

  describe "ErrorJSON" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.ErrorJSON)
    end
  end
end
