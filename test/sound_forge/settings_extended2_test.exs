defmodule SoundForge.SettingsExtended2Test do
  @moduledoc """
  Tests for Settings context functions not covered by existing tests:
  change_user_settings/2 and save_lalalai_api_key/2.
  """
  use SoundForge.DataCase

  alias SoundForge.Settings

  import SoundForge.AccountsFixtures

  describe "change_user_settings/2" do
    test "returns changeset for new settings" do
      changeset =
        Settings.change_user_settings(%SoundForge.Accounts.UserSettings{}, %{
          download_quality: "128k"
        })

      assert %Ecto.Changeset{} = changeset
    end

    test "returns changeset for existing settings" do
      user = user_fixture()
      {:ok, settings} = Settings.save_user_settings(user.id, %{download_quality: "256k"})
      changeset = Settings.change_user_settings(settings, %{download_quality: "320k"})
      assert %Ecto.Changeset{} = changeset
    end

    test "returns changeset with empty attrs" do
      changeset = Settings.change_user_settings(%SoundForge.Accounts.UserSettings{}, %{})
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "save_lalalai_api_key/2" do
    test "saves api key for user without existing settings" do
      user = user_fixture()
      result = Settings.save_lalalai_api_key(user.id, "test-lalalai-key-123")
      assert {:ok, settings} = result
      assert settings.lalalai_api_key == "test-lalalai-key-123"
    end

    test "saves api key for user with existing settings" do
      user = user_fixture()
      Settings.save_user_settings(user.id, %{download_quality: "256k"})
      result = Settings.save_lalalai_api_key(user.id, "updated-key-456")
      assert {:ok, settings} = result
      assert settings.lalalai_api_key == "updated-key-456"
    end

    test "overwrites existing api key" do
      user = user_fixture()
      Settings.save_lalalai_api_key(user.id, "first-key")
      {:ok, settings} = Settings.save_lalalai_api_key(user.id, "second-key")
      assert settings.lalalai_api_key == "second-key"
    end
  end
end
