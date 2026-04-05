defmodule SoundForge.Music.SpotifyTest do
  @moduledoc "Tests for Music.Spotify delegation module."
  use ExUnit.Case, async: true

  alias SoundForge.Music.Spotify

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Spotify)
    end

    test "fetch_metadata/1 is exported" do
      assert {:fetch_metadata, 1} in Spotify.__info__(:functions)
    end

    test "delegates to SoundForge.Spotify" do
      # The module delegates fetch_metadata to SoundForge.Spotify
      # We verify the delegation exists by checking both modules have the function
      assert {:fetch_metadata, 1} in SoundForge.Spotify.__info__(:functions)
    end
  end
end
