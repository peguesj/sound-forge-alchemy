defmodule SoundForge.DJ.ChefSet do
  @moduledoc """
  A named collection of AI-generated cue/loop markers for a track.

  Chef sets are created by the Chef AI system (AutoCueWorker variant) and
  can be saved, loaded, and swapped on a deck. Each set has a type (cue_set,
  loop_set, hot_cue_set) and contains ordered ChefSetItems.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @set_types ~w(cue_set loop_set hot_cue_set)
  @sources ~w(chef manual)

  schema "chef_sets" do
    field :name, :string
    field :set_type, :string, default: "cue_set"
    field :source, :string, default: "chef"
    field :generation_opts, :map, default: %{}

    belongs_to :user, SoundForge.Accounts.User, type: :integer, foreign_key: :user_id
    belongs_to :track, SoundForge.Music.Track

    has_many :items, SoundForge.DJ.ChefSetItem,
      foreign_key: :chef_set_id,
      on_delete: :delete_all

    timestamps()
  end

  @type t :: %__MODULE__{}

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = chef_set, attrs) do
    chef_set
    |> cast(attrs, [:name, :set_type, :source, :generation_opts, :user_id, :track_id])
    |> validate_required([:name, :set_type, :user_id, :track_id])
    |> validate_inclusion(:set_type, @set_types)
    |> validate_inclusion(:source, @sources)
    |> validate_length(:name, min: 1, max: 100)
  end
end
