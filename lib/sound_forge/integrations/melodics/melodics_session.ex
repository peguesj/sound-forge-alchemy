defmodule SoundForge.Integrations.Melodics.MelodicsSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :integer

  schema "melodics_sessions" do
    field :lesson_name, :string
    field :accuracy, :float
    field :bpm, :integer
    field :instrument, :string
    field :practiced_at, :utc_datetime

    belongs_to :user, SoundForge.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(lesson_name user_id)a
  @optional_fields ~w(accuracy bpm instrument practiced_at)a

  def changeset(session, attrs) do
    session
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:accuracy, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0)
    |> validate_number(:bpm, greater_than: 0)
    |> foreign_key_constraint(:user_id)
  end
end
