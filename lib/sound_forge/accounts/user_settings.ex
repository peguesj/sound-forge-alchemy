defmodule SoundForge.Accounts.UserSettings do
  @moduledoc """
  Per-user preference overrides. All fields are nullable -- nil means
  "use the global default from Application config".
  """
  use Ecto.Schema
  import Ecto.Changeset

  @valid_qualities ~w(128k 192k 256k 320k)
  @valid_formats ~w(mp3 flac wav ogg)
  @valid_demucs_models ~w(htdemucs htdemucs_ft htdemucs_6s mdx_extra)
  @valid_demucs_output ~w(wav flac mp3)
  @valid_demucs_devices ~w(cpu cuda)
  @valid_analysis_features ~w(tempo key energy spectral)
  @valid_lalalai_splitters ~w(andromeda perseus orion phoenix lyra)
  @valid_lalalai_extraction_levels ~w(mild normal clear_cut deep_extraction)
  @valid_lalalai_output_formats ~w(mp3 wav flac aac ogg)

  schema "user_settings" do
    belongs_to :user, SoundForge.Accounts.User

    # Spotify / Downloads
    field :download_quality, :string
    field :audio_format, :string
    field :output_directory, :string

    # YouTube / yt-dlp
    field :ytdlp_search_depth, :integer
    field :ytdlp_preferred_format, :string
    field :ytdlp_bitrate, :string

    # Demucs
    field :demucs_model, :string
    field :demucs_output_format, :string
    field :demucs_device, :string
    field :demucs_timeout, :integer

    # Analysis
    field :analysis_features, {:array, :string}
    field :analyzer_timeout, :integer

    # Storage
    field :storage_path, :string
    field :max_file_age_days, :integer
    field :retention_days, :integer

    # General
    field :tracks_per_page, :integer
    field :max_upload_size, :integer

    # Cloud Separation (encrypted at rest via Cloak AES-GCM-256)
    field :lalalai_api_key, SoundForge.Encrypted.Binary
    field :lalalai_splitter, :string
    field :lalalai_dereverb, :boolean
    field :lalalai_extraction_level, :string
    field :lalalai_output_format, :string

    # Debug
    field :debug_mode, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :download_quality,
    :audio_format,
    :output_directory,
    :ytdlp_search_depth,
    :ytdlp_preferred_format,
    :ytdlp_bitrate,
    :demucs_model,
    :demucs_output_format,
    :demucs_device,
    :demucs_timeout,
    :analysis_features,
    :analyzer_timeout,
    :storage_path,
    :max_file_age_days,
    :retention_days,
    :tracks_per_page,
    :max_upload_size,
    :lalalai_api_key,
    :lalalai_splitter,
    :lalalai_dereverb,
    :lalalai_extraction_level,
    :lalalai_output_format,
    :debug_mode
  ]

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, @cast_fields)
    |> validate_inclusion(:download_quality, @valid_qualities)
    |> validate_inclusion(:audio_format, @valid_formats)
    |> validate_inclusion(:demucs_model, @valid_demucs_models)
    |> validate_inclusion(:demucs_output_format, @valid_demucs_output)
    |> validate_inclusion(:demucs_device, @valid_demucs_devices)
    |> validate_number(:ytdlp_search_depth, greater_than: 0, less_than_or_equal_to: 20)
    |> validate_number(:demucs_timeout, greater_than: 0)
    |> validate_number(:analyzer_timeout, greater_than: 0)
    |> validate_number(:max_file_age_days, greater_than: 0)
    |> validate_number(:retention_days, greater_than: 0)
    |> validate_number(:tracks_per_page, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:max_upload_size, greater_than: 0)
    |> validate_subset(:analysis_features, @valid_analysis_features)
    |> validate_inclusion(:lalalai_splitter, @valid_lalalai_splitters)
    |> validate_inclusion(:lalalai_extraction_level, @valid_lalalai_extraction_levels)
    |> validate_inclusion(:lalalai_output_format, @valid_lalalai_output_formats)
  end

  @section_fields %{
    spotify: [:download_quality, :audio_format, :output_directory],
    downloads: [:download_quality, :audio_format, :output_directory],
    youtube: [:ytdlp_search_depth, :ytdlp_preferred_format, :ytdlp_bitrate],
    demucs: [:demucs_model, :demucs_output_format, :demucs_device, :demucs_timeout],
    analysis: [:analysis_features, :analyzer_timeout],
    storage: [:storage_path, :max_file_age_days, :retention_days],
    cloud_separation: [:lalalai_api_key, :lalalai_splitter, :lalalai_dereverb, :lalalai_extraction_level, :lalalai_output_format],
    general: [:tracks_per_page, :max_upload_size]
  }

  def section_fields, do: @section_fields

  def reset_section_changeset(settings, section) do
    fields = Map.get(@section_fields, section, [])
    nil_attrs = Map.new(fields, &{&1, nil})
    cast(settings, nil_attrs, fields)
  end
end
