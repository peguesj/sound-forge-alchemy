defmodule SoundForgeWeb.DashboardLalalaiTest do
  @moduledoc """
  Tests for DashboardLive lalalai modal, key management,
  engine selection, and task cancellation handlers.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Lalalai Track",
        artist: "Lalalai Artist",
        duration: 200
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/lalalai_test.mp3"
    })

    %{track: track}
  end

  describe "engine selection" do
    test "select_engine lalalai", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_engine", %{"engine" => "lalalai"})
      assert is_binary(html)
    end

    test "select_engine demucs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_engine", %{"engine" => "demucs"})
      assert is_binary(html)
    end
  end

  describe "lalalai modal" do
    test "close_lalalai_modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "close_lalalai_modal", %{})
      assert is_binary(html)
    end

    test "expand_lalalai_key_form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "expand_lalalai_key_form", %{})
      assert is_binary(html)
    end

    test "lalalai_modal_key_input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "lalalai_modal_key_input", %{"key" => "test-key-123"})
      assert is_binary(html)
    end

    test "test_save_lalalai_key", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "lalalai_modal_key_input", %{"key" => "test-key-abc"})
      html = render_click(view, "test_save_lalalai_key", %{})
      assert is_binary(html)
    end

    test "test_lalalai_connection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "test_lalalai_connection", %{})
      assert is_binary(html)
    end
  end

  describe "lalalai mode settings" do
    test "select_lalalai_mode vocals_and_instrumentals", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "vocals_and_instrumentals"})
      assert is_binary(html)
    end

    test "select_lalalai_mode multistem", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "multistem"})
      assert is_binary(html)
    end

    test "select_lalalai_mode voice_clean", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "voice_clean"})
      assert is_binary(html)
    end

    test "toggle_multistem drums", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_multistem", %{"stem" => "drums"})
      assert is_binary(html)
    end

    test "toggle_multistem bass", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_multistem", %{"stem" => "bass"})
      assert is_binary(html)
    end

    test "set_noise_level", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "set_noise_level", %{"level" => "2"})
      assert is_binary(html)
    end

    test "select_voice_pack", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_voice_pack", %{"pack_id" => "pack-1"})
      assert is_binary(html)
    end

    test "set_accent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "set_accent", %{"value" => "0.5"})
      assert is_binary(html)
    end

    test "toggle_dereverb", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_dereverb", %{})
      assert is_binary(html)
    end
  end

  describe "lalalai task management" do
    test "cancel_all_lalalai_tasks with no active tasks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "cancel_all_lalalai_tasks", %{})
      assert is_binary(html)
    end

    test "cancel_all_lalalai_tasks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "cancel_all_lalalai_tasks", %{})
      assert is_binary(html)
    end
  end

  describe "toggle_preview" do
    test "toggle_preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_preview", %{})
      assert is_binary(html)
    end
  end

  describe "toggle_auto_download" do
    test "toggle_auto_download", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_auto_download", %{})
      assert is_binary(html)
    end
  end
end
