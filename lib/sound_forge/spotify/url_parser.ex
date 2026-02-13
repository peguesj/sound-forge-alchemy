defmodule SoundForge.Spotify.URLParser do
  @moduledoc """
  Parses Spotify URLs to extract type and ID.

  Supports standard Spotify URLs for tracks, albums, and playlists.
  """

  @spotify_regex ~r{(?:https?://)?(?:open\.)?spotify\.com/(?:intl-\w+/)?(track|album|playlist)/([a-zA-Z0-9]+)}

  @doc """
  Parses a Spotify URL and extracts the type and ID.

  ## Examples

      iex> SoundForge.Spotify.URLParser.parse("https://open.spotify.com/track/abc123")
      {:ok, %{type: "track", id: "abc123"}}

      iex> SoundForge.Spotify.URLParser.parse("spotify.com/album/xyz789")
      {:ok, %{type: "album", id: "xyz789"}}

      iex> SoundForge.Spotify.URLParser.parse("invalid-url")
      {:error, :invalid_spotify_url}
  """
  @spec parse(String.t()) ::
          {:ok, %{type: String.t(), id: String.t()}} | {:error, :invalid_spotify_url}
  def parse(url) when is_binary(url) do
    case Regex.run(@spotify_regex, url) do
      [_, type, id] -> {:ok, %{type: type, id: id}}
      _ -> {:error, :invalid_spotify_url}
    end
  end

  def parse(_), do: {:error, :invalid_spotify_url}
end
