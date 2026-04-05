defmodule SoundForgeWeb.SpotifyPlayerTest do
  @moduledoc """
  Tests for SpotifyPlayer LiveComponent module loading and exports.
  SpotifyPlayer is a LiveComponent that wraps the Spotify Web Playback SDK.
  Direct interaction testing is limited since it requires Spotify OAuth token.
  """
  use ExUnit.Case, async: true

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.Live.Components.SpotifyPlayer)
    end

    test "exports handle_event/3" do
      assert {:handle_event, 3} in SoundForgeWeb.Live.Components.SpotifyPlayer.__info__(:functions)
    end

    test "exports update/2" do
      assert {:update, 2} in SoundForgeWeb.Live.Components.SpotifyPlayer.__info__(:functions)
    end

    test "exports mount/1" do
      assert {:mount, 1} in SoundForgeWeb.Live.Components.SpotifyPlayer.__info__(:functions)
    end
  end
end
