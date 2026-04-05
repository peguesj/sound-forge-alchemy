defmodule SoundForge.ControlSurface.DeviceProfile do
  @moduledoc """
  Schema for persisting control surface device profiles and mappings.

  A device profile represents a collection of control mappings for a specific
  hardware controller (MIDI, OSC, etc.). Profiles can be created via:

    - `:manual` - User-created via MIDI Learn
    - `:tsi` - Imported from Traktor TSI XML
    - `:rekordbox` - Imported from Rekordbox XML
    - `:touchosc` - Imported from TouchOSC JSON layout
    - `:midi_learn` - Auto-generated via MIDI Learn UI

  ## Mappings Structure

  The `mappings` field is a map of control IDs to action specs:

      %{
        "cc:0:1" => %{
          "action" => :stem_volume,
          "params" => %{"target" => "master"}
        },
        "note_on:0:48" => %{
          "action" => :dj_play,
          "params" => %{"deck" => "1"}
        }
      }

  For OSC devices, control IDs are OSC address patterns:

      %{
        "/stem/1/volume" => %{
          "action" => :stem_volume,
          "params" => %{"stem" => "1"}
        }
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary() | nil,
          name: String.t(),
          vendor: String.t() | nil,
          source: atom(),
          device_id: String.t() | nil,
          mappings: map(),
          user_id: integer() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @sources [:manual, :tsi, :rekordbox, :touchosc, :midi_learn]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "device_profiles" do
    field :name, :string
    field :vendor, :string
    field :source, Ecto.Enum, values: @sources
    field :device_id, :string
    field :mappings, :map, default: %{}

    belongs_to :user, SoundForge.Accounts.User, type: :integer

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name source)a
  @optional_fields ~w(vendor device_id mappings user_id)a

  @doc false
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:vendor, max: 255)
    |> validate_length(:device_id, max: 255)
    |> validate_inclusion(:source, @sources)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Returns the list of valid source types.
  """
  @spec sources() :: [atom()]
  def sources, do: @sources
end
