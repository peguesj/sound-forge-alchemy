defmodule SoundForge.Spotify.Client do
  @moduledoc """
  Behaviour for Spotify Web API client.

  This behaviour allows for easy mocking in tests while providing
  a clear interface for Spotify API interactions.
  """

  @callback fetch_track(String.t()) :: {:ok, map()} | {:error, term()}
  @callback fetch_album(String.t()) :: {:ok, map()} | {:error, term()}
  @callback fetch_playlist(String.t()) :: {:ok, map()} | {:error, term()}
end
