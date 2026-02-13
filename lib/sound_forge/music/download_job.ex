defmodule SoundForge.Music.DownloadJob do
  @moduledoc """
  Schema for tracking audio download jobs from Spotify via spotdl.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_values [:queued, :downloading, :processing, :completed, :failed]

  schema "download_jobs" do
    field :status, Ecto.Enum, values: @status_values, default: :queued
    field :progress, :integer, default: 0
    field :output_path, :string
    field :file_size, :integer
    field :error, :string

    belongs_to :track, SoundForge.Music.Track

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(download_job, attrs) do
    download_job
    |> cast(attrs, [:track_id, :status, :progress, :output_path, :file_size, :error])
    |> validate_required([:track_id])
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:track_id)
  end
end
