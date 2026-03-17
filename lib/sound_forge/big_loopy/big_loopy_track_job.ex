defmodule SoundForge.BigLoopy.BigLoopyTrackJob do
  @moduledoc """
  Embedded schema representing the arguments for a BigLoopyTrackWorker job.

  Each track processed in a BigLoopy pipeline gets its own typed job struct.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :track_id, :binary_id
    field :alchemy_set_id, :binary_id
    field :stem_type, :string
    # JSON-encoded list of %{start: float, end: float, label: string} loop point maps
    field :loop_points, {:array, :map}, default: []
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(job, attrs) do
    job
    |> cast(attrs, [:track_id, :alchemy_set_id, :stem_type, :loop_points])
    |> validate_required([:track_id, :alchemy_set_id])
  end
end
