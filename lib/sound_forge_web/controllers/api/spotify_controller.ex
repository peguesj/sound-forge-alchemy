defmodule SoundForgeWeb.API.SpotifyController do
  @moduledoc """
  Controller for Spotify metadata fetching operations.
  """
  use SoundForgeWeb, :controller

  action_fallback SoundForgeWeb.API.FallbackController

  def fetch(conn, %{"url" => url}) when is_binary(url) and url != "" do
    case SoundForge.Spotify.fetch_metadata(url) do
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
end
