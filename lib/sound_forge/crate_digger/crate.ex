defmodule SoundForge.CrateDigger.Crate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "crates" do
    field :name, :string
    field :spotify_playlist_id, :string
    field :playlist_data, {:array, :map}, default: []
    field :stem_config, :map, default: %{"enabled_stems" => ["vocals", "drums", "bass", "other"]}

    belongs_to :user, SoundForge.Accounts.User, type: :integer
    has_many :track_configs, SoundForge.CrateDigger.CrateTrackConfig

    timestamps()
  end

  @doc false
  def changeset(crate, attrs) do
    crate
    |> cast(attrs, [:name, :spotify_playlist_id, :playlist_data, :stem_config, :user_id])
    |> validate_required([:name, :spotify_playlist_id, :user_id])
  end
end
