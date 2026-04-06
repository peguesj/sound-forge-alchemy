defmodule SoundForge.CrateDigger.CrateTrackConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "crate_track_configs" do
    field :spotify_track_id, :string
    field :stem_override, :map

    belongs_to :crate, SoundForge.CrateDigger.Crate

    timestamps()
  end

  @doc false
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:spotify_track_id, :stem_override, :crate_id])
    |> validate_required([:spotify_track_id, :crate_id])
  end
end
