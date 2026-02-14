defmodule SoundForgeWeb.SpotifyOAuthControllerTest do
  use SoundForgeWeb.ConnCase, async: true

  setup :register_and_log_in_user

  describe "GET /auth/spotify" do
    test "redirects to Spotify authorization", %{conn: conn} do
      conn = get(conn, ~p"/auth/spotify")
      assert redirected_to(conn) =~ "accounts.spotify.com/authorize"
    end

    test "sets oauth state in session", %{conn: conn} do
      conn = get(conn, ~p"/auth/spotify")
      assert get_session(conn, :spotify_oauth_state)
    end
  end

  describe "GET /auth/spotify/callback with error" do
    test "redirects to settings with error flash", %{conn: conn} do
      conn = get(conn, ~p"/auth/spotify/callback", %{error: "access_denied"})
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "denied"
    end
  end

  describe "GET /auth/spotify/callback with invalid state" do
    test "rejects callback with mismatched state", %{conn: conn} do
      # Set a known state in session
      conn = conn |> Plug.Test.init_test_session(%{spotify_oauth_state: "valid_state"})

      conn = get(conn, ~p"/auth/spotify/callback", %{code: "test_code", state: "wrong_state"})
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid OAuth state"
    end
  end
end
