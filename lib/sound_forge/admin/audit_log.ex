defmodule SoundForge.Admin.AuditLog do
  @moduledoc """
  Schema for admin audit trail entries.
  Records who did what to which resource and when.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :changes, :map, default: %{}
    field :ip_address, :string

    belongs_to :actor, SoundForge.Accounts.User, type: :id

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(action resource_type)a
  @optional_fields ~w(resource_id changes ip_address actor_id)a

  @doc "Casts and validates attributes for an audit log entry."
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:action, ~w(
      create update delete suspend ban reactivate
      role_change bulk_role_change config_update
      feature_flag_toggle login logout
    ))
  end
end
