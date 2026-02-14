defmodule SoundForge.Accounts.UserSettingsTest do
  use SoundForge.DataCase, async: true

  alias SoundForge.Accounts.UserSettings

  describe "changeset/2" do
    test "valid changeset with spotify/download fields" do
      changeset =
        UserSettings.changeset(%UserSettings{}, %{
          download_quality: "320k",
          audio_format: "flac"
        })

      assert changeset.valid?
    end

    test "valid changeset with demucs fields" do
      changeset =
        UserSettings.changeset(%UserSettings{}, %{
          demucs_model: "htdemucs_ft",
          demucs_output_format: "wav",
          demucs_device: "cpu",
          demucs_timeout: 600_000
        })

      assert changeset.valid?
    end

    test "validates download_quality inclusion" do
      changeset =
        UserSettings.changeset(%UserSettings{}, %{download_quality: "999k"})

      assert %{download_quality: [_]} = errors_on(changeset)
    end

    test "validates audio_format inclusion" do
      changeset =
        UserSettings.changeset(%UserSettings{}, %{audio_format: "aac"})

      assert %{audio_format: [_]} = errors_on(changeset)
    end

    test "accepts valid audio formats" do
      for format <- ~w(mp3 flac wav ogg) do
        changeset =
          UserSettings.changeset(%UserSettings{}, %{audio_format: format})

        assert changeset.valid?, "Expected #{format} to be valid"
      end
    end

    test "validates demucs_model inclusion" do
      changeset =
        UserSettings.changeset(%UserSettings{}, %{demucs_model: "nonexistent"})

      assert %{demucs_model: [_]} = errors_on(changeset)
    end

    test "accepts valid demucs models" do
      for model <- ~w(htdemucs htdemucs_ft htdemucs_6s mdx_extra) do
        changeset =
          UserSettings.changeset(%UserSettings{}, %{demucs_model: model})

        assert changeset.valid?, "Expected #{model} to be valid"
      end
    end

    test "validates demucs_output_format inclusion" do
      changeset =
        UserSettings.changeset(%UserSettings{}, %{demucs_output_format: "aac"})

      assert %{demucs_output_format: [_]} = errors_on(changeset)
    end

    test "validates demucs_device inclusion" do
      changeset =
        UserSettings.changeset(%UserSettings{}, %{demucs_device: "tpu"})

      assert %{demucs_device: [_]} = errors_on(changeset)
    end

    test "validates ytdlp_search_depth range" do
      too_low = UserSettings.changeset(%UserSettings{}, %{ytdlp_search_depth: 0})
      assert %{ytdlp_search_depth: [_]} = errors_on(too_low)

      too_high = UserSettings.changeset(%UserSettings{}, %{ytdlp_search_depth: 21})
      assert %{ytdlp_search_depth: [_]} = errors_on(too_high)

      valid = UserSettings.changeset(%UserSettings{}, %{ytdlp_search_depth: 10})
      assert valid.valid?
    end

    test "validates demucs_timeout must be positive" do
      changeset = UserSettings.changeset(%UserSettings{}, %{demucs_timeout: 0})
      assert %{demucs_timeout: [_]} = errors_on(changeset)
    end

    test "validates analyzer_timeout must be positive" do
      changeset = UserSettings.changeset(%UserSettings{}, %{analyzer_timeout: -1})
      assert %{analyzer_timeout: [_]} = errors_on(changeset)
    end

    test "validates max_file_age_days must be positive" do
      changeset = UserSettings.changeset(%UserSettings{}, %{max_file_age_days: 0})
      assert %{max_file_age_days: [_]} = errors_on(changeset)
    end

    test "validates tracks_per_page range" do
      too_low = UserSettings.changeset(%UserSettings{}, %{tracks_per_page: 0})
      assert %{tracks_per_page: [_]} = errors_on(too_low)

      too_high = UserSettings.changeset(%UserSettings{}, %{tracks_per_page: 101})
      assert %{tracks_per_page: [_]} = errors_on(too_high)

      valid = UserSettings.changeset(%UserSettings{}, %{tracks_per_page: 50})
      assert valid.valid?
    end

    test "validates max_upload_size must be positive" do
      changeset = UserSettings.changeset(%UserSettings{}, %{max_upload_size: 0})
      assert %{max_upload_size: [_]} = errors_on(changeset)
    end

    test "validates analysis_features subset" do
      invalid =
        UserSettings.changeset(%UserSettings{}, %{
          analysis_features: ["tempo", "invalid"]
        })

      assert %{analysis_features: [_]} = errors_on(invalid)

      valid =
        UserSettings.changeset(%UserSettings{}, %{
          analysis_features: ["tempo", "key", "energy"]
        })

      assert valid.valid?
    end

    test "allows all fields to be nil (empty changeset)" do
      changeset = UserSettings.changeset(%UserSettings{}, %{})
      assert changeset.valid?
    end
  end

  describe "section_fields/0" do
    test "returns map of section names to field lists" do
      fields = UserSettings.section_fields()
      assert is_map(fields)
      assert :spotify in Map.keys(fields)
      assert :demucs in Map.keys(fields)
      assert :analysis in Map.keys(fields)
      assert :storage in Map.keys(fields)
      assert :general in Map.keys(fields)
    end

    test "spotify section contains expected fields" do
      fields = UserSettings.section_fields()
      assert :download_quality in fields.spotify
      assert :audio_format in fields.spotify
    end
  end

  describe "reset_section_changeset/2" do
    test "sets section fields to nil" do
      settings = %UserSettings{
        download_quality: "320k",
        audio_format: "flac",
        demucs_model: "htdemucs"
      }

      changeset = UserSettings.reset_section_changeset(settings, :spotify)

      assert Ecto.Changeset.get_change(changeset, :download_quality) == nil
      assert Ecto.Changeset.get_change(changeset, :audio_format) == nil
      # demucs field should not be changed
      refute Ecto.Changeset.get_change(changeset, :demucs_model)
    end

    test "handles unknown section gracefully" do
      changeset = UserSettings.reset_section_changeset(%UserSettings{}, :unknown)
      assert changeset.valid?
    end
  end
end
