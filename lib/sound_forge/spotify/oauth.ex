defmodule SoundForge.Spotify.OAuth do
  @moduledoc """
  Spotify OAuth2 Authorization Code flow.

  Handles building the authorize URL, exchanging codes for tokens,
  refreshing expired tokens, and encrypting tokens at rest.
  """

  require Logger

  alias SoundForge.Repo
  alias SoundForge.Accounts.SpotifyOAuthToken

  import Ecto.Query

  @authorize_url "https://accounts.spotify.com/authorize"
  @token_url "https://accounts.spotify.com/api/token"
  @scopes "playlist-read-private user-library-read user-read-playback-state user-top-read streaming user-modify-playback-state user-read-private user-read-email"

  @doc "Builds the Spotify authorization URL for the given state parameter."
  def authorize_url(state) do
    config = spotify_config()
    client_id = config[:client_id]

    if is_nil(client_id) or client_id == "" do
      raise "SPOTIFY_CLIENT_ID is not configured. Set it in .env or as an environment variable."
    end

    params =
      URI.encode_query(%{
        response_type: "code",
        client_id: client_id,
        scope: @scopes,
        redirect_uri: redirect_uri(),
        state: state
      })

    "#{@authorize_url}?#{params}"
  end

  @doc "Generates a random state token for CSRF protection."
  def generate_state do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  @doc """
  Generates a signed state token that embeds the user_id.

  This is necessary because the OAuth callback redirect may arrive on a different
  origin (127.0.0.1 vs localhost), causing session cookies to be unavailable.
  The user_id is signed with the endpoint's secret to prevent tampering.
  """
  def generate_state_with_user(user_id) do
    csrf = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    payload = "#{csrf}:#{user_id}"
    signature = sign_state(payload)
    Base.url_encode64("#{payload}:#{signature}", padding: false)
  end

  @doc "Extracts the user_id from a signed state token. Returns {csrf_part, user_id} or :error."
  def extract_user_from_state(state) do
    with {:ok, decoded} <- Base.url_decode64(state, padding: false),
         [csrf, user_id_str, signature] <- String.split(decoded, ":", parts: 3),
         payload = "#{csrf}:#{user_id_str}",
         ^signature <- sign_state(payload),
         {user_id, ""} <- Integer.parse(user_id_str) do
      {:ok, user_id}
    else
      _ -> :error
    end
  end

  defp sign_state(payload) do
    secret = Application.get_env(:sound_forge, SoundForgeWeb.Endpoint)[:secret_key_base]
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.url_encode64(padding: false)
  end

  @doc "Exchanges an authorization code for access + refresh tokens."
  def exchange_code(code, _state) do
    config = spotify_config()

    body =
      URI.encode_query(%{
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirect_uri()
      })

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"authorization",
       "Basic #{Base.encode64("#{config[:client_id]}:#{config[:client_secret]}")}"}
    ]

    case Req.post(@token_url, body: body, headers: headers) do
      {:ok, %{status: 200, body: token_body}} ->
        {:ok, parse_token_response(token_body)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Spotify token exchange failed: #{status} - #{inspect(body)}")
        {:error, "Token exchange failed (#{status})"}

      {:error, reason} ->
        Logger.error("Spotify token request failed: #{inspect(reason)}")
        {:error, "Token request failed"}
    end
  end

  @doc "Refreshes an expired access token using the refresh token."
  def refresh_token(%SpotifyOAuthToken{} = token) do
    config = spotify_config()
    decrypted_refresh = decrypt(token.refresh_token)

    body =
      URI.encode_query(%{
        grant_type: "refresh_token",
        refresh_token: decrypted_refresh
      })

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"authorization",
       "Basic #{Base.encode64("#{config[:client_id]}:#{config[:client_secret]}")}"}
    ]

    case Req.post(@token_url, body: body, headers: headers) do
      {:ok, %{status: 200, body: token_body}} ->
        {:ok, parse_token_response(token_body)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Spotify token refresh failed: #{status} - #{inspect(body)}")
        {:error, "Token refresh failed (#{status})"}

      {:error, reason} ->
        Logger.error("Spotify token refresh request failed: #{inspect(reason)}")
        {:error, "Token refresh failed"}
    end
  end

  @doc "Saves (encrypts + upserts) OAuth tokens for a user."
  def save_token(user_id, token_data) when is_map(token_data) do
    unless is_binary(token_data.access_token) do
      Logger.warning("save_token called with non-binary access_token for user #{user_id}")
    end

    attrs = %{
      user_id: user_id,
      access_token: encrypt(token_data.access_token),
      refresh_token: encrypt(token_data.refresh_token),
      token_type: token_data[:token_type] || "Bearer",
      expires_at: token_data.expires_at,
      scopes: token_data[:scopes] || @scopes
    }

    case Repo.get_by(SpotifyOAuthToken, user_id: user_id) do
      %SpotifyOAuthToken{} = existing ->
        existing
        |> SpotifyOAuthToken.changeset(attrs)
        |> Repo.update()

      nil ->
        %SpotifyOAuthToken{}
        |> SpotifyOAuthToken.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc "Returns a valid (auto-refreshed) decrypted access token, or error."
  def get_valid_access_token(user_id) do
    case Repo.get_by(SpotifyOAuthToken, user_id: user_id) do
      nil ->
        {:error, :not_linked}

      %SpotifyOAuthToken{} = token ->
        if SpotifyOAuthToken.expired?(token) do
          case refresh_token(token) do
            {:ok, %{access_token: access_token} = new_data} when is_binary(access_token) ->
              # Preserve existing refresh_token if Spotify didn't return a new one
              new_data =
                if is_nil(new_data.refresh_token),
                  do: %{new_data | refresh_token: decrypt(token.refresh_token)},
                  else: new_data

              {:ok, _} = save_token(user_id, new_data)
              {:ok, new_data.access_token}

            {:ok, %{access_token: nil}} ->
              Logger.error("Spotify refresh returned nil access_token for user #{user_id}")
              {:error, :refresh_failed}

            error ->
              error
          end
        else
          {:ok, decrypt(token.access_token)}
        end
    end
  end

  @doc "Returns true if the user has linked their Spotify account."
  def linked?(user_id) do
    Repo.exists?(from t in SpotifyOAuthToken, where: t.user_id == ^user_id)
  end

  @doc "Removes the user's Spotify OAuth tokens."
  def unlink(user_id) do
    case Repo.get_by(SpotifyOAuthToken, user_id: user_id) do
      %SpotifyOAuthToken{} = token -> Repo.delete(token)
      nil -> {:ok, nil}
    end
  end

  # -- Private --

  defp parse_token_response(body) do
    expires_in = body["expires_in"] || 3600

    expires_at =
      DateTime.add(DateTime.utc_now(), expires_in, :second) |> DateTime.truncate(:second)

    %{
      access_token: body["access_token"],
      refresh_token: body["refresh_token"],
      token_type: body["token_type"] || "Bearer",
      expires_at: expires_at,
      scopes: body["scope"]
    }
  end

  defp encrypt(nil), do: nil

  defp encrypt(plaintext) when is_binary(plaintext) do
    Phoenix.Token.encrypt(SoundForgeWeb.Endpoint, "spotify_oauth", plaintext, max_age: :infinity)
  end

  defp decrypt(ciphertext) when is_binary(ciphertext) do
    case Phoenix.Token.decrypt(SoundForgeWeb.Endpoint, "spotify_oauth", ciphertext,
           max_age: :infinity
         ) do
      {:ok, plaintext} -> plaintext
      {:error, _} -> nil
    end
  end

  defp spotify_config do
    Application.get_env(:sound_forge, :spotify, [])
  end

  defp redirect_uri do
    Application.get_env(
      :sound_forge,
      :spotify_redirect_uri,
      SoundForgeWeb.Endpoint.url() <> "/auth/spotify/callback"
    )
  end
end
