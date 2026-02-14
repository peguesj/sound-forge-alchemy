defmodule SoundForge.SettingsTest do
  use SoundForge.DataCase, async: true

  alias SoundForge.Settings
  alias SoundForge.Accounts.UserSettings

  import SoundForge.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "defaults/0" do
    test "returns a map with all default keys" do
      defaults = Settings.defaults()
      assert is_map(defaults)
      assert defaults.download_quality == "320k"
      assert defaults.demucs_model == "htdemucs"
      assert defaults.tracks_per_page == 24
      assert defaults.analysis_features == ["tempo", "key", "energy", "spectral"]
    end
  end

  describe "default/1" do
    test "returns default value for known key" do
      assert Settings.default(:download_quality) == "320k"
      assert Settings.default(:tracks_per_page) == 24
    end

    test "returns nil for unknown key" do
      assert Settings.default(:nonexistent_key) == nil
    end
  end

  describe "get/2" do
    test "returns global default when no user settings exist", %{user: user} do
      assert Settings.get(user.id, :download_quality) == "320k"
    end

    test "returns user override when set", %{user: user} do
      {:ok, _} = Settings.save_user_settings(user.id, %{download_quality: "192k"})
      assert Settings.get(user.id, :download_quality) == "192k"
    end

    test "returns global default when user field is nil", %{user: user} do
      {:ok, _} = Settings.save_user_settings(user.id, %{demucs_model: "htdemucs_ft"})
      assert Settings.get(user.id, :download_quality) == "320k"
    end

    test "works with nil user_id" do
      assert Settings.get(nil, :download_quality) == "320k"
    end
  end

  describe "get_effective/1" do
    test "returns all defaults when no user settings exist", %{user: user} do
      effective = Settings.get_effective(user.id)
      assert effective.download_quality == "320k"
      assert effective.demucs_model == "htdemucs"
    end

    test "merges user overrides over defaults", %{user: user} do
      {:ok, _} =
        Settings.save_user_settings(user.id, %{
          download_quality: "256k",
          demucs_model: "mdx_extra"
        })

      effective = Settings.get_effective(user.id)
      assert effective.download_quality == "256k"
      assert effective.demucs_model == "mdx_extra"
      assert effective.tracks_per_page == 24
    end
  end

  describe "save_user_settings/2" do
    test "creates settings for new user", %{user: user} do
      assert {:ok, %UserSettings{} = settings} =
               Settings.save_user_settings(user.id, %{download_quality: "256k"})

      assert settings.download_quality == "256k"
      assert settings.user_id == user.id
    end

    test "updates existing settings", %{user: user} do
      {:ok, _} = Settings.save_user_settings(user.id, %{download_quality: "256k"})
      {:ok, updated} = Settings.save_user_settings(user.id, %{download_quality: "192k"})
      assert updated.download_quality == "192k"
    end

    test "validates invalid values", %{user: user} do
      assert {:error, changeset} =
               Settings.save_user_settings(user.id, %{download_quality: "999k"})

      assert errors_on(changeset).download_quality
    end

    test "validates number ranges", %{user: user} do
      assert {:error, changeset} =
               Settings.save_user_settings(user.id, %{tracks_per_page: 0})

      assert errors_on(changeset).tracks_per_page
    end

    test "validates analysis features subset", %{user: user} do
      assert {:error, changeset} =
               Settings.save_user_settings(user.id, %{analysis_features: ["invalid_feature"]})

      assert errors_on(changeset).analysis_features
    end
  end

  describe "reset_section/2" do
    test "resets section fields to nil", %{user: user} do
      {:ok, _} =
        Settings.save_user_settings(user.id, %{
          download_quality: "256k",
          audio_format: "flac",
          demucs_model: "mdx_extra"
        })

      {:ok, _} = Settings.reset_section(user.id, :spotify)

      settings = Settings.get_user_settings(user.id)
      assert settings.download_quality == nil
      assert settings.audio_format == nil
      # Demucs field should remain
      assert settings.demucs_model == "mdx_extra"
    end

    test "returns ok when no settings exist", %{user: user} do
      assert {:ok, nil} = Settings.reset_section(user.id, :spotify)
    end
  end

  describe "change_user_settings/2" do
    test "returns a changeset" do
      changeset = Settings.change_user_settings(%UserSettings{})
      assert %Ecto.Changeset{} = changeset
    end
  end
end
