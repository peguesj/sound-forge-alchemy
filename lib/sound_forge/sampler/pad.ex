defmodule SoundForge.Sampler.Pad do
  @moduledoc """
  Schema for an individual pad within a sampler bank.

  Each pad occupies an `index` (0..15) within its parent bank and may
  optionally reference a stem for audio playback. Pads store playback
  parameters: volume, pitch shift, velocity sensitivity, and
  waveform start/end selection points.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          index: integer(),
          label: String.t() | nil,
          color: String.t() | nil,
          volume: float(),
          pitch: float(),
          velocity: float(),
          start_time: float(),
          end_time: float() | nil,
          bank_id: binary(),
          stem_id: binary() | nil,
          bank: SoundForge.Sampler.Bank.t() | Ecto.Association.NotLoaded.t(),
          stem: SoundForge.Music.Stem.t() | nil | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sampler_pads" do
    field :index, :integer
    field :label, :string
    field :color, :string, default: "#6b7280"
    field :volume, :float, default: 1.0
    field :pitch, :float, default: 0.0
    field :velocity, :float, default: 1.0
    field :start_time, :float, default: 0.0
    field :end_time, :float

    belongs_to :bank, SoundForge.Sampler.Bank
    belongs_to :stem, SoundForge.Music.Stem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pad, attrs) do
    pad
    |> cast(attrs, [:index, :label, :color, :volume, :pitch, :velocity, :start_time, :end_time, :bank_id, :stem_id])
    |> validate_required([:index, :bank_id])
    |> validate_number(:index, greater_than_or_equal_to: 0, less_than: 16)
    |> validate_number(:volume, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:pitch, greater_than_or_equal_to: -24.0, less_than_or_equal_to: 24.0)
    |> validate_number(:velocity, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:start_time, greater_than_or_equal_to: 0.0)
    |> unique_constraint([:bank_id, :index])
    |> foreign_key_constraint(:bank_id)
    |> foreign_key_constraint(:stem_id)
  end
end
