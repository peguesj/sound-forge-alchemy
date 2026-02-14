defmodule SoundForgeWeb.SpotifyOAuthController do
  use SoundForgeWeb, :controller

  alias SoundForge.Spotify.OAuth

  def authorize(conn, _params) do
    user_id = conn.assigns.current_scope.user.id
    state = OAuth.generate_state_with_user(user_id)
    url = OAuth.authorize_url(state)

    conn
    |> put_session(:spotify_oauth_state, state)
    |> redirect(external: url)
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    # Extract user_id from signed state token (survives cross-origin redirects
    # where session cookies may not be sent, e.g. localhost vs 127.0.0.1)
    case OAuth.extract_user_from_state(state) do
      {:ok, user_id} ->
        handle_oauth_callback(conn, code, user_id, state)

      :error ->
        conn
        |> put_flash(:error, "Invalid OAuth state. Please try linking Spotify again.")
        |> redirect(to: ~p"/")
    end
  end

  def callback(conn, %{"error" => error}) do
    message =
      case error do
        "access_denied" -> "Spotify authorization was denied."
        other -> "Spotify authorization error: #{other}"
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/")
  end

  defp handle_oauth_callback(conn, code, user_id, state) do
    case OAuth.exchange_code(code, state) do
      {:ok, token_data} ->
        case OAuth.save_token(user_id, token_data) do
          {:ok, _} ->
            conn
            |> delete_session(:spotify_oauth_state)
            |> put_flash(:info, "Spotify account linked successfully.")
            |> redirect(to: ~p"/")

          {:error, _} ->
            conn
            |> put_flash(:error, "Failed to save Spotify tokens.")
            |> redirect(to: ~p"/")
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, "Spotify authorization failed: #{reason}")
        |> redirect(to: ~p"/")
    end
  end
end
