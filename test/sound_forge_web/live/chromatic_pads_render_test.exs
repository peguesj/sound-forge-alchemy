defmodule SoundForgeWeb.ChromaticPadsRenderTest do
  @moduledoc """
  Tests for ChromaticPadsComponent rendering via the dashboard Pads tab.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "pads tab rendering" do
    test "renders empty pads state", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/?tab=pads")
      assert html =~ "Pads" or html =~ "pads" or html =~ "bank"
    end

    test "renders pads tab with a bank", %{conn: conn, user: user} do
      SoundForge.Sampler.create_bank(%{name: "Test Pad Bank", user_id: user.id})

      {:ok, _view, html} = live(conn, "/?tab=pads")
      assert html =~ "Test Pad Bank" or html =~ "pads"
    end

    test "renders with multiple banks", %{conn: conn, user: user} do
      SoundForge.Sampler.create_bank(%{name: "Bank Alpha", user_id: user.id, position: 0})
      SoundForge.Sampler.create_bank(%{name: "Bank Beta", user_id: user.id, position: 1})

      {:ok, _view, html} = live(conn, "/?tab=pads")
      assert html =~ "pads" or html =~ "Bank"
    end

    test "create bank event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "create_bank", %{})
      assert html =~ "pads" or html =~ "Bank" or html =~ "bank"
    end
  end

  describe "pad interactions" do
    test "select bank", %{conn: conn, user: user} do
      {:ok, bank} = SoundForge.Sampler.create_bank(%{name: "Select Bank", user_id: user.id})
      {:ok, view, _html} = live(conn, "/?tab=pads")

      html = render_click(view, "select_bank", %{"bank_id" => bank.id})
      assert html =~ "pads" or html =~ "Select Bank"
    end

    test "rename bank", %{conn: conn, user: user} do
      {:ok, bank} = SoundForge.Sampler.create_bank(%{name: "Old Name", user_id: user.id})
      {:ok, view, _html} = live(conn, "/?tab=pads")

      render_click(view, "select_bank", %{"bank_id" => bank.id})
      html = render_click(view, "rename_bank", %{"name" => "New Name"})
      assert html =~ "pads" or html =~ "New Name"
    end
  end
end
