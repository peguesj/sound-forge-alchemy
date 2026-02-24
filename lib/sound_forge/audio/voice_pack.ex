defmodule SoundForge.Audio.VoicePack do
  @moduledoc """
  Schema for caching voice pack metadata from remote sources.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          pack_id: String.t(),
          name: String.t(),
          created_at_remote: DateTime.t() | nil,
          cached_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "voice_packs" do
    field :pack_id, :string
    field :name, :string
    field :created_at_remote, :utc_datetime
    field :cached_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(voice_pack, attrs) do
    voice_pack
    |> cast(attrs, [:pack_id, :name, :created_at_remote, :cached_at])
    |> validate_required([:pack_id, :name])
    |> unique_constraint(:pack_id)
  end
end
