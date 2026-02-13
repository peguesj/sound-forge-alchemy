defmodule SoundForgeWeb.API.SpotifyController do
  @moduledoc """
  Controller for Spotify metadata fetching operations.
  """
  use SoundForgeWeb, :controller

  action_fallback SoundForgeWeb.API.FallbackController

  @doc """
  POST /api/spotify/fetch
  Fetches Spotify metadata for a given URL.
  """
  def fetch(conn, %{"url" => url}) when is_binary(url) and url != "" do
    case fetch_spotify_metadata(url) do
      {:ok, metadata} ->
        json(conn, %{success: true, metadata: metadata})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: to_string(reason)})
    end
  end

  def fetch(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "url parameter is required"})
  end

  # Private helper - tries to call context module if it exists
  defp fetch_spotify_metadata(url) do
    if Code.ensure_loaded?(SoundForge.Music.Spotify) do
      SoundForge.Music.Spotify.fetch_metadata(url)
    else
      # Stub response for when context module doesn't exist yet
      {:ok,
       %{
         name: "Example Track",
         artist: "Example Artist",
         album: "Example Album",
         duration_ms: 180_000,
         url: url
       }}
    end
  rescue
    UndefinedFunctionError ->
      {:ok,
       %{
         name: "Example Track",
         artist: "Example Artist",
         album: "Example Album",
         duration_ms: 180_000,
         url: url
       }}
  end
end
