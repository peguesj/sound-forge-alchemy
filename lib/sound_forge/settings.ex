defmodule SoundForge.Settings do
  @moduledoc """
  Settings context: per-user preferences with global config fallback.

  Resolution order: user DB value (non-nil) -> global Application config default.
  """

  alias SoundForge.Repo
  alias SoundForge.Accounts.UserSettings
  import Ecto.Changeset

  @defaults_map %{
    download_quality: {:sound_forge, :download_quality, "320k"},
    audio_format: {:sound_forge, :audio_format, "mp3"},
    output_directory: {:sound_forge, :downloads_dir, "priv/uploads/downloads"},
    ytdlp_search_depth: {:sound_forge, :ytdlp_search_depth, 5},
    ytdlp_preferred_format: {:sound_forge, :ytdlp_preferred_format, "bestaudio"},
    ytdlp_bitrate: {:sound_forge, :ytdlp_bitrate, "320k"},
    demucs_model: {:sound_forge, :default_demucs_model, "htdemucs"},
    demucs_output_format: {:sound_forge, :demucs_output_format, "wav"},
    demucs_device: {:sound_forge, :demucs_device, "cpu"},
    demucs_timeout: {:sound_forge, :demucs_timeout, 300_000},
    analysis_features: {:sound_forge, :analysis_features, ["tempo", "key", "energy", "spectral"]},
    analyzer_timeout: {:sound_forge, :analyzer_timeout, 120_000},
    storage_path: {:sound_forge, :storage_path, "priv/uploads"},
    max_file_age_days: {:sound_forge, :max_file_age_days, 30},
    retention_days: {:sound_forge, :retention_days, 90},
    tracks_per_page: {:sound_forge, :tracks_per_page, 24},
    max_upload_size: {:sound_forge, :max_upload_size, 100_000_000},
    lalalai_api_key: {:sound_forge, :lalalai_api_key, nil},
    lalalai_splitter: {:sound_forge, :lalalai_splitter, "phoenix"},
    lalalai_dereverb: {:sound_forge, :lalalai_dereverb, false},
    lalalai_extraction_level: {:sound_forge, :lalalai_extraction_level, "clear_cut"},
    lalalai_output_format: {:sound_forge, :lalalai_output_format, nil},
    debug_mode: {:sound_forge, :debug_mode, false}
  }

  @doc "Returns the global defaults map (key -> resolved default value)."
  def defaults do
    Map.new(@defaults_map, fn {key, {app, config_key, fallback}} ->
      {key, Application.get_env(app, config_key, fallback)}
    end)
  end

  @doc "Returns the default value for a single key."
  def default(key) when is_atom(key) do
    case Map.fetch(@defaults_map, key) do
      {:ok, {app, config_key, fallback}} -> Application.get_env(app, config_key, fallback)
      :error -> nil
    end
  end

  @doc "Fetches the user_settings record for a user (or nil)."
  def get_user_settings(user_id) when is_integer(user_id) do
    Repo.get_by(UserSettings, user_id: user_id)
  end

  def get_user_settings(_), do: nil

  @doc """
  Resolves a single setting for a user.
  Returns the user's override if set, otherwise the global default.
  """
  def get(user_id, key) when is_atom(key) do
    case get_user_settings(user_id) do
      %UserSettings{} = s ->
        case Map.get(s, key) do
          nil -> default(key)
          val -> val
        end

      nil ->
        default(key)
    end
  end

  @doc "Returns a full map of effective settings (user overrides merged over defaults)."
  def get_effective(user_id) do
    defs = defaults()

    case get_user_settings(user_id) do
      %UserSettings{} = s ->
        Map.new(defs, fn {key, default_val} ->
          {key, Map.get(s, key) || default_val}
        end)

      nil ->
        defs
    end
  end

  @doc "Returns a changeset for the settings form."
  def change_user_settings(%UserSettings{} = settings, attrs \\ %{}) do
    UserSettings.changeset(settings, attrs)
  end

  @doc "Upserts user settings (creates or updates)."
  def save_user_settings(user_id, attrs) when is_integer(user_id) do
    case get_user_settings(user_id) do
      %UserSettings{} = existing ->
        existing
        |> UserSettings.changeset(attrs)
        |> Repo.update()

      nil ->
        %UserSettings{user_id: user_id}
        |> UserSettings.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc "Saves the lalal.ai API key for a user."
  def save_lalalai_api_key(user_id, api_key) when is_integer(user_id) do
    case get_user_settings(user_id) do
      %UserSettings{} = existing ->
        existing
        |> cast(%{lalalai_api_key: api_key}, [:lalalai_api_key])
        |> Repo.update()

      nil ->
        %UserSettings{user_id: user_id}
        |> cast(%{lalalai_api_key: api_key}, [:lalalai_api_key])
        |> Repo.insert()
    end
  end

  @doc "Resets all fields in a section to nil (use global defaults)."
  def reset_section(user_id, section) when is_atom(section) do
    case get_user_settings(user_id) do
      %UserSettings{} = s ->
        s
        |> UserSettings.reset_section_changeset(section)
        |> Repo.update()

      nil ->
        {:ok, nil}
    end
  end
end
