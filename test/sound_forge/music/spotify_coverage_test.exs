defmodule SoundForge.Music.SpotifyCoverageTest do
  @moduledoc "Tests for Music.Spotify namespace wrapper."
  use ExUnit.Case, async: true

  alias SoundForge.Music.Spotify

  describe "fetch_metadata/1" do
    test "returns error for invalid URL" do
      result = Spotify.fetch_metadata("not-a-valid-spotify-url")
      assert match?({:error, _}, result)
    end

    test "returns error for empty string" do
      result = Spotify.fetch_metadata("")
      assert match?({:error, _}, result)
    end
  end
end
