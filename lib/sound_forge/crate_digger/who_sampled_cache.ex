defmodule SoundForge.CrateDigger.WhoSampledCache do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "who_sampled_cache" do
    field :spotify_track_id, :string
    field :raw_data, {:array, :map}, default: []
    field :fetched_at, :utc_datetime

    timestamps()
  end

  @doc false
  def changeset(cache, attrs) do
    cache
    |> cast(attrs, [:spotify_track_id, :raw_data, :fetched_at])
    |> validate_required([:spotify_track_id, :fetched_at])
    |> unique_constraint(:spotify_track_id)
  end
end
