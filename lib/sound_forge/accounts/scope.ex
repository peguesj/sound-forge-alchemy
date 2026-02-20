defmodule SoundForge.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `SoundForge.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.
  """

  alias SoundForge.Accounts.User

  defstruct user: nil, role: :user, admin?: false

  @role_hierarchy [:user, :pro, :enterprise, :admin, :super_admin]

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{role: role} = user) do
    %__MODULE__{
      user: user,
      role: role,
      admin?: role in [:admin, :super_admin]
    }
  end

  def for_user(nil), do: nil

  @doc "Returns the numeric level for a role (higher = more privileged)."
  def role_level(role) when role in @role_hierarchy do
    Enum.find_index(@role_hierarchy, &(&1 == role))
  end

  @doc "Checks if the scope's role meets or exceeds the minimum required role."
  def has_role?(%__MODULE__{role: role}, minimum_role) do
    role_level(role) >= role_level(minimum_role)
  end

  def has_role?(nil, _), do: false

  @doc "Can the user manage other users (admin+)?"
  def can_manage_users?(%__MODULE__{} = scope), do: has_role?(scope, :admin)
  def can_manage_users?(_), do: false

  @doc "Can the user view platform analytics (admin+)?"
  def can_view_analytics?(%__MODULE__{} = scope), do: has_role?(scope, :admin)
  def can_view_analytics?(_), do: false

  @doc "Can the user configure system settings (super_admin only)?"
  def can_configure_system?(%__MODULE__{} = scope), do: has_role?(scope, :super_admin)
  def can_configure_system?(_), do: false

  @doc "Can the user access a specific feature based on role gating?"
  def can_use_feature?(%__MODULE__{role: role}, feature) do
    case feature do
      :stem_separation -> role in [:pro, :enterprise, :admin, :super_admin]
      :lalalai_cloud -> role in [:enterprise, :admin, :super_admin]
      :osc_touchosc -> role in [:enterprise, :admin, :super_admin]
      :midi_control -> role in [:pro, :enterprise, :admin, :super_admin]
      :melodics -> role in [:pro, :enterprise, :admin, :super_admin]
      :full_analysis -> role in [:pro, :enterprise, :admin, :super_admin]
      :admin_dashboard -> role in [:admin, :super_admin]
      :feature_flags -> role == :super_admin
      :billing -> role == :super_admin
      _ -> true
    end
  end

  def can_use_feature?(_, _), do: false
end
