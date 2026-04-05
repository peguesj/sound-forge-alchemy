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

  Accepts a user struct or map with an `:id` key. Looks up the user's stored
  OAuth token via `SoundForge.Spotify.OAuth.get_valid_access_token/1`, which
  handles expiry and refresh automatically.

  Returns `{:ok, [playlist_map]}` or `{:error, reason}`.

  Each playlist_map has keys: `"id"`, `"name"`, `"tracks_total"`, `"url"`, `"image_url"`.
  """
  @spec list_user_playlists(map() | nil) ::
          {:ok, [map()]} | {:error, term()}
  def list_user_playlists(nil), do: {:error, :not_authenticated}

  def list_user_playlists(user) do
    user_id = Map.get(user, :id)

    case SoundForge.Spotify.OAuth.get_valid_access_token(user_id) do
      {:ok, token} ->
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

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extract a Spotify playlist ID from a URL, URI, or bare ID.

  Handles:
  - Full URL: `https://open.spotify.com/playlist/37i9dQZEVXbNG2KDcFEKwX`
  - URI: `spotify:playlist:37i9dQZEVXbNG2KDcFEKwX`
  - Bare ID: `37i9dQZEVXbNG2KDcFEKwX`

  Returns `{:ok, playlist_id}` or `{:error, :invalid_playlist_id}`.
  """
  @spec extract_playlist_id(String.t()) :: {:ok, String.t()} | {:error, :invalid_playlist_id}
  def extract_playlist_id(input) when is_binary(input) do
    input = String.trim(input)

    cond do
      # Full Spotify URL
      String.contains?(input, "spotify.com") ->
        case URLParser.parse(input) do
          {:ok, %{type: "playlist", id: id}} -> {:ok, id}
          _ -> {:error, :invalid_playlist_id}
        end

      # Spotify URI: spotify:playlist:<id>
      String.starts_with?(input, "spotify:playlist:") ->
        id = String.replace_prefix(input, "spotify:playlist:", "")
        if valid_spotify_id?(id), do: {:ok, id}, else: {:error, :invalid_playlist_id}

      # Bare ID (alphanumeric, 22 chars is standard but allow reasonable range)
      valid_spotify_id?(input) ->
        {:ok, input}

      true ->
        {:error, :invalid_playlist_id}
    end
  end

  def extract_playlist_id(_), do: {:error, :invalid_playlist_id}

  @doc """
  Fetch all tracks from a Spotify playlist using a user OAuth access token.

  Handles Spotify API pagination via the `next` field. Returns
  `{:ok, [track_map]}` or `{:error, reason}`.

  Each track map has keys: `spotify_id`, `name`, `artist`, `album`,
  `duration_ms`, `preview_url`.
  """
  @spec get_playlist_tracks(String.t(), String.t()) ::
          {:ok, [map()]} | {:error, term()}
  def get_playlist_tracks(playlist_id, access_token) when is_binary(playlist_id) and is_binary(access_token) do
    url = "https://api.spotify.com/v1/playlists/#{playlist_id}/tracks?limit=100"
    fetch_playlist_tracks_page(url, access_token, [])
  end

  defp fetch_playlist_tracks_page(nil, _token, acc), do: {:ok, Enum.reverse(acc)}

  defp fetch_playlist_tracks_page(url, token, acc) do
    opts = [headers: [{"Authorization", "Bearer #{token}"}]]

    case Req.get(url, opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        items = body["items"] || []

        tracks =
          items
          |> Enum.reject(fn item -> is_nil(item["track"]) end)
          |> Enum.map(fn item ->
            t = item["track"]
            %{
              "spotify_id" => t["id"],
              "name" => t["name"],
              "artist" => (get_in(t, ["artists", Access.at(0), "name"]) || ""),
              "album" => get_in(t, ["album", "name"]) || "",
              "duration_ms" => t["duration_ms"],
              "preview_url" => t["preview_url"]
            }
          end)
          |> Enum.reject(fn t -> is_nil(t["spotify_id"]) end)

        fetch_playlist_tracks_page(body["next"], token, Enum.reverse(tracks) ++ acc)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:api_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_spotify_id?(id) when is_binary(id) do
    String.length(id) >= 10 and String.match?(id, ~r/^[a-zA-Z0-9]+$/)
  end

  defp valid_spotify_id?(_), do: false

  defp spotify_client do
    Application.get_env(:sound_forge, :spotify_client, SoundForge.Spotify.HTTPClient)
  end
end
