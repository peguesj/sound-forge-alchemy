defmodule SoundForge.DJ.DjPreset do
  @moduledoc """
  Schema for persisted DJ session layout snapshots.

  A preset captures the complete state of the DJ tab at a point in time:
  deck assignments, tempo, pitch, loop, EQ, crossfader, cue points, and
  stem states. The `layout_json` field stores all of this as a map.

  Sources:
  - `"manual"` — saved directly from the DJ tab UI
  - `"tsi"` — imported from a Traktor .tsi controller mapping file
  - `"touchosc"` — imported from a TouchOSC .touchosc layout file
  - `"rekordbox"` — imported from a Pioneer Rekordbox .xml export
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :id

  schema "dj_presets" do
    field :name, :string
    field :layout_json, :map
    field :source, :string, default: "manual"
    field :format_version, :string, default: "1.0"

    belongs_to :user, SoundForge.Accounts.User

    timestamps()
  end

  @valid_sources ~w(manual tsi touchosc rekordbox)

  @doc "Changeset for creating a new preset."
  def create_changeset(preset, attrs) do
    preset
    |> cast(attrs, [:name, :user_id, :layout_json, :source, :format_version])
    |> validate_required([:name, :user_id, :layout_json])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_inclusion(:source, @valid_sources)
  end

  @doc "Changeset for updating a preset's name only."
  def update_changeset(preset, attrs) do
    preset
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 120)
  end
end
