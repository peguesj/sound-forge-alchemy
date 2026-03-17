defmodule SoundForge.BigLoopy.BigLoopyJob do
  @moduledoc """
  Embedded schema representing the arguments for a BigLoopy orchestrator job.

  Used as typed job arguments for BigLoopyOrchestratorWorker.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :job_type, :string, default: "standard"
    field :alchemy_set_id, :binary_id
    field :user_id, :integer
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(job, attrs) do
    job
    |> cast(attrs, [:job_type, :alchemy_set_id, :user_id])
    |> validate_required([:alchemy_set_id, :user_id])
  end
end
