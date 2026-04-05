defmodule SoundForgeWeb.SpotifyOAuthControllerExtendedTest do
  @moduledoc """
  Extended Spotify OAuth controller tests: additional error callback branches.
  """
  use SoundForgeWeb.ConnCase, async: true

  setup :register_and_log_in_user

  describe "GET /auth/spotify/callback with generic error" do
    test "shows generic error message for non-access_denied errors", %{conn: conn} do
      conn = get(conn, ~p"/auth/spotify/callback", %{error: "server_error"})
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "server_error"
    end

    test "shows specific message for access_denied", %{conn: conn} do
      conn = get(conn, ~p"/auth/spotify/callback", %{error: "access_denied"})
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "denied"
    end
  end
end
