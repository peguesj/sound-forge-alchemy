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

  defp spotify_client do
    Application.get_env(:sound_forge, :spotify_client, SoundForge.Spotify.HTTPClient)
  end
end
