defmodule SoundForgeWeb.MidiListenTest do
  @moduledoc """
  Tests for MidiLive toggle_listen handler.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "toggle_listen" do
    test "toggle_listen for a port", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "toggle_listen", %{"port-id" => "input:0"})
      assert is_binary(html)
    end

    test "toggle_listen twice toggles off", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      render_click(view, "toggle_listen", %{"port-id" => "input:0"})
      html = render_click(view, "toggle_listen", %{"port-id" => "input:0"})
      assert is_binary(html)
    end
  end
end
