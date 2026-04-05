defmodule SoundForgeWeb.PrototypeLiveTest do
  @moduledoc """
  Tests for PrototypeLive.
  Note: PrototypeLive requires Mix.env() == :dev AND admin role.
  In test env, mount redirects with error flash. We test the redirect behavior
  and module loading.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "access control" do
    test "redirects non-admin users in test env", %{conn: conn} do
      {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/prototype")
    end

    test "redirects with flash", %{conn: conn} do
      {:error, {:redirect, %{flash: flash}}} = live(conn, ~p"/prototype")
      assert is_map(flash)
    end

    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.PrototypeLive)
    end
  end

  describe "exports" do
    test "exports handle_params/3" do
      assert {:handle_params, 3} in SoundForgeWeb.PrototypeLive.__info__(:functions)
    end

    test "exports handle_event/3" do
      assert {:handle_event, 3} in SoundForgeWeb.PrototypeLive.__info__(:functions)
    end

    test "exports handle_info/2" do
      assert {:handle_info, 2} in SoundForgeWeb.PrototypeLive.__info__(:functions)
    end
  end
end
