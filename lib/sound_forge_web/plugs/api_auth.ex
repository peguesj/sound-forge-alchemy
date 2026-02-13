defmodule SoundForgeWeb.Plugs.APIAuth do
  @moduledoc """
  Authenticates API requests via Bearer token.
  The token is a user session token from the accounts system.
  """
  import Plug.Conn

  alias SoundForge.Accounts
  alias SoundForge.Accounts.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.url_decode64(token, padding: false),
         {user, _inserted_at} when not is_nil(user) <- Accounts.get_user_by_session_token(decoded) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> assign(:current_user, user)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Unauthorized", message: "Valid Bearer token required"}))
        |> halt()
    end
  end
end
