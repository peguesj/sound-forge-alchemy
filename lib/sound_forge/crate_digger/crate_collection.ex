defmodule SoundForge.CrateDigger.CrateCollection do
  @moduledoc """
  A CrateCollection groups multiple Crates into a named folder/workspace.

  Analogous to a Spotify folder — a user might have a "Summer Set" collection
  containing several playlists of similar genre/energy.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "crate_collections" do
    field :name, :string
    field :description, :string
    field :metadata, :map, default: %{}

    belongs_to :user, SoundForge.Accounts.User, type: :integer
    has_many :crates, SoundForge.CrateDigger.Crate

    timestamps()
  end

  @doc false
  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:name, :description, :metadata, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 100)
  end
end
