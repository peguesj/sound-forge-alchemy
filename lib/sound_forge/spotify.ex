defmodule SoundForge.Spotify do
  @moduledoc """
  Context module for Spotify integration.

  Provides functionality to fetch metadata from Spotify for tracks, albums, and playlists.
  """

  alias SoundForge.Spotify.URLParser

  @doc """
  Fetches metadata for a Spotify URL.

  Parses the URL to determine the resource type (track, album, or playlist)
  and fetches the corresponding metadata from the Spotify Web API.

  ## Examples

      iex> SoundForge.Spotify.fetch_metadata("https://open.spotify.com/track/abc123")
      {:ok, %{"id" => "abc123", "name" => "Song Name", ...}}

      iex> SoundForge.Spotify.fetch_metadata("invalid-url")
      {:error, :invalid_spotify_url}
  """
  @spec fetch_metadata(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_metadata(url) do
    with {:ok, %{type: type, id: id}} <- URLParser.parse(url) do
      client = spotify_client()

      case type do
        "track" -> client.fetch_track(id)
        "album" -> client.fetch_album(id)
        "playlist" -> client.fetch_playlist(id)
      end
    end
  end

  @doc """
  Fetch the current user's playlists from Spotify.

  Requires a user-level OAuth access token stored on the user struct as
  `spotify_access_token`. Returns `{:ok, [playlist_map]}` or `{:error, reason}`.

  Each playlist_map has keys: `"id"`, `"name"`, `"tracks_total"`, `"url"`, `"image_url"`.
  """
  @spec list_user_playlists(map() | nil) ::
          {:ok, [map()]} | {:error, term()}
  def list_user_playlists(nil), do: {:error, :not_authenticated}

  def list_user_playlists(user) do
    token = user[:spotify_access_token] || Map.get(user, :spotify_access_token)

    if is_nil(token) do
      {:error, :no_spotify_token}
    else
      url = "https://api.spotify.com/v1/me/playlists?limit=50"
      opts = [headers: [{"Authorization", "Bearer #{token}"}]]

      case Req.get(url, opts) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          items = body["items"] || []
          playlists =
            Enum.map(items, fn p ->
              %{
                "id" => p["id"],
                "name" => p["name"],
                "tracks_total" => get_in(p, ["tracks", "total"]) || 0,
                "url" => "https://open.spotify.com/playlist/#{p["id"]}",
                "image_url" => get_in(p, ["images", Access.at(0), "url"])
              }
            end)

          {:ok, playlists}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:api_error, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp spotify_client do
    Application.get_env(:sound_forge, :spotify_client, SoundForge.Spotify.HTTPClient)
  end
end
