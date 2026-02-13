defmodule SoundForge.Music.Spotify do
  @moduledoc """
  Namespace wrapper that delegates Spotify operations to the `SoundForge.Spotify` context.
  """

  defdelegate fetch_metadata(url), to: SoundForge.Spotify
end
