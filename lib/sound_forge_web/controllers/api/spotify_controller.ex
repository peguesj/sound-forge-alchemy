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
        message =
          case reason do
            msg when is_binary(msg) -> msg
            {:api_error, status, _body} -> "Spotify API error (#{status})"
            atom when is_atom(atom) -> to_string(atom)
            other -> inspect(other)
          end

        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  def fetch(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "url parameter is required"})
  end
end
