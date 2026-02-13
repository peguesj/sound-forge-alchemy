defmodule SoundForge.Spotify.HTTPClient do
  @moduledoc """
  HTTP client for Spotify Web API using OAuth client credentials flow.

  Implements token caching via ETS to avoid unnecessary token requests.
  Tokens are cached for 3500 seconds (Spotify tokens expire in 3600s).
  """

  @behaviour SoundForge.Spotify.Client

  require Logger

  @token_url "https://accounts.spotify.com/api/token"
  @api_base_url "https://api.spotify.com/v1"
  @default_token_ttl 3500
  @token_table :spotify_tokens

  @doc """
  Initializes the ETS table for token caching.
  Should be called when the application starts.
  """
  def init do
    :ets.new(@token_table, [:named_table, :public, :set])
  rescue
    ArgumentError -> :already_exists
  end

  @impl true
  def fetch_track(id) do
    fetch_resource("tracks", id)
  end

  @impl true
  def fetch_album(id) do
    fetch_resource("albums", id)
  end

  @impl true
  def fetch_playlist(id) do
    fetch_resource("playlists", id)
  end

  defp fetch_resource(resource_type, id) do
    with {:ok, token} <- get_access_token(),
         {:ok, response} <- make_api_request(resource_type, id, token) do
      {:ok, response.body}
    else
      {:error, %Req.Response{status: status, body: body}} ->
        Logger.error("Spotify API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} = error ->
        Logger.error("Spotify request failed: #{inspect(reason)}")
        error
    end
  end

  defp make_api_request(resource_type, id, token) do
    url = "#{@api_base_url}/#{resource_type}/#{id}"

    case Req.get(url, headers: [{"Authorization", "Bearer #{token}"}]) do
      {:ok, %Req.Response{status: 200} = response} ->
        {:ok, response}

      {:ok, response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_access_token do
    case get_cached_token() do
      {:ok, token} ->
        {:ok, token}

      :error ->
        fetch_and_cache_token()
    end
  end

  defp get_cached_token do
    init()

    case :ets.lookup(@token_table, :access_token) do
      [{:access_token, token, expires_at}] ->
        if System.system_time(:second) < expires_at do
          {:ok, token}
        else
          :error
        end

      [] ->
        :error
    end
  end

  defp fetch_and_cache_token do
    with {:ok, config} <- get_spotify_config(),
         {:ok, token} <- request_token(config) do
      cache_token(token)
      {:ok, token}
    end
  end

  defp request_token(config) do
    auth = Base.encode64("#{config.client_id}:#{config.client_secret}")

    body = %{grant_type: "client_credentials"}

    headers = [
      {"Authorization", "Basic #{auth}"},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    case Req.post(@token_url, form: body, headers: headers) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Token request failed: #{status} - #{inspect(body)}")
        {:error, {:token_error, status, body}}

      {:error, reason} ->
        Logger.error("Token request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp cache_token(token) do
    ttl = Application.get_env(:sound_forge, :spotify_token_ttl, @default_token_ttl)
    expires_at = System.system_time(:second) + ttl
    :ets.insert(@token_table, {:access_token, token, expires_at})
  end

  defp get_spotify_config do
    config = Application.get_env(:sound_forge, :spotify, [])

    client_id = Keyword.get(config, :client_id)
    client_secret = Keyword.get(config, :client_secret)

    cond do
      is_nil(client_id) or client_id == "" ->
        {:error, :missing_client_id}

      is_nil(client_secret) or client_secret == "" ->
        {:error, :missing_client_secret}

      true ->
        {:ok, %{client_id: client_id, client_secret: client_secret}}
    end
  end
end
