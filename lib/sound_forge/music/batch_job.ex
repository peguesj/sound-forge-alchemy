defmodule SoundForge.Music.BatchJob do
  @moduledoc """
  Schema for grouping multiple processing jobs into a single batch operation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          status: :pending | :processing | :completed | :failed,
          total_count: integer(),
          completed_count: integer(),
          options: map() | nil,
          user_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_values [:pending, :processing, :completed, :failed]

  schema "batch_jobs" do
    field :status, Ecto.Enum, values: @status_values, default: :pending
    field :total_count, :integer
    field :completed_count, :integer, default: 0
    field :options, :map

    belongs_to :user, SoundForge.Accounts.User, type: :id
    has_many :processing_jobs, SoundForge.Music.ProcessingJob

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(batch_job, attrs) do
    batch_job
    |> cast(attrs, [:user_id, :status, :total_count, :completed_count, :options])
    |> validate_required([:user_id, :total_count])
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:total_count, greater_than: 0)
    |> validate_number(:completed_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
  end
end
