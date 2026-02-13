defmodule SoundForgeWeb.Plugs.APIAuth do
  @moduledoc """
  Authenticates API requests via Bearer token.
  The token is a user session token from the accounts system.
  Validates token age against a configurable TTL (default: 30 days).
  """
  import Plug.Conn

  alias SoundForge.Accounts
  alias SoundForge.Accounts.Scope

  @default_token_ttl_days 30

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.url_decode64(token, padding: false),
         {user, inserted_at} when not is_nil(user) <- Accounts.get_user_by_session_token(decoded),
         :ok <- validate_token_age(inserted_at) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> assign(:current_user, user)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          401,
          Jason.encode!(%{error: "Unauthorized", message: "Valid Bearer token required"})
        )
        |> halt()
    end
  end

  defp validate_token_age(inserted_at) do
    ttl_days = Application.get_env(:sound_forge, :api_token_ttl_days, @default_token_ttl_days)
    max_age_seconds = ttl_days * 86_400

    age = DateTime.diff(DateTime.utc_now(), inserted_at, :second)

    if age <= max_age_seconds, do: :ok, else: :expired
  end
end
