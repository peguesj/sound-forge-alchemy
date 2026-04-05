defmodule SoundForge.Music.SpotifyModuleTest do
  @moduledoc "Tests for Music.Spotify delegate module."
  use ExUnit.Case, async: true

  alias SoundForge.Music.Spotify

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Spotify)
    end

    test "fetch_metadata/1 is exported" do
      assert {:fetch_metadata, 1} in Spotify.__info__(:functions)
    end
  end
end
