defmodule SoundForgeWeb.Live.Components.SpotifyPlayerTest do
  @moduledoc "Tests for SpotifyPlayer LiveComponent."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.SpotifyPlayer

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SpotifyPlayer)
    end

    test "mount/1 is exported" do
      assert {:mount, 1} in SpotifyPlayer.__info__(:functions)
    end

    test "update/2 is exported" do
      assert {:update, 2} in SpotifyPlayer.__info__(:functions)
    end

    test "render/1 is exported" do
      assert {:render, 1} in SpotifyPlayer.__info__(:functions)
    end
  end

  describe "mount/1" do
    test "returns ok tuple" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      assert {:ok, _mounted} = SpotifyPlayer.mount(socket)
    end
  end

  describe "update/2" do
    test "accepts playback assigns" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          spotify_premium: false
        }
      }

      assigns = %{
        id: "sp-player",
        playback: nil,
        spotify_linked: false,
        spotify_premium: true
      }

      {:ok, updated} = SpotifyPlayer.update(assigns, socket)
      assert updated.assigns.id == "sp-player"
      assert updated.assigns.spotify_linked == false
      assert updated.assigns.spotify_premium == true
    end
  end

  describe "render in dashboard" do
    setup :register_and_log_in_user

    test "dashboard footer includes spotify player area", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      # The SpotifyPlayer renders in the dashboard footer
      # It will show the "not linked" bar since user hasn't linked Spotify
      assert html =~ "Spotify" or html =~ "spotify" or html =~ "player"
    end
  end
end
