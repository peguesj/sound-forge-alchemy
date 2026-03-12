defmodule SoundForgeWeb.ImpersonateController do
  @moduledoc """
  Dev-only controller for user impersonation.

  Allows admin+ users to impersonate any seed/demo user by swapping
  the session token. Stores the original user ID so we can restore.
  Only available when `:dev_routes` is enabled.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Accounts
  alias SoundForgeWeb.UserAuth

  def create(conn, %{"user_id" => user_id}) do
    current_user = conn.assigns.current_user

    unless current_user.role in [:admin, :super_admin, :platform_admin] do
      conn
      |> put_flash(:error, "Only admin users can impersonate.")
      |> redirect(to: ~p"/prototype?tab=devtools")
      |> halt()
    end

    target_user = Accounts.get_user!(user_id)

    conn
    |> put_session(:impersonator_id, current_user.id)
    |> UserAuth.log_in_user(target_user, %{"remember_me" => "false"})
  end

  def delete(conn, _params) do
    impersonator_id = get_session(conn, :impersonator_id)

    if impersonator_id do
      original_user = Accounts.get_user!(impersonator_id)

      conn
      |> delete_session(:impersonator_id)
      |> UserAuth.log_in_user(original_user, %{"remember_me" => "false"})
    else
      conn
      |> put_flash(:info, "Not currently impersonating.")
      |> redirect(to: ~p"/")
    end
  end
end
