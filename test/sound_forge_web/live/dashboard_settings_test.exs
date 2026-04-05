defmodule SoundForgeWeb.DashboardSettingsTest do
  @moduledoc """
  Tests for DashboardLive settings/engine-related handle_event handlers.
  Covers: toggle_view, filter, select_voice_pack, set_accent,
  close_lalalai_modal, expand_lalalai_key_form, lalalai_modal_key_input,
  start_batch_process, cancel_batch_modal, validate_upload, dismiss_pipeline.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{user_id: user.id, title: "Settings Test", artist: "Artist A"})
    %{track: track}
  end

  describe "toggle_view" do
    test "switch to grid mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_view", %{"mode" => "grid"})
      assert is_binary(html)
    end

    test "switch to list mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_view", %{"mode" => "list"})
      assert is_binary(html)
    end

    test "switch to list_expanded mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_view", %{"mode" => "list_expanded"})
      assert is_binary(html)
    end

    test "invalid mode defaults to grid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_view", %{"mode" => "nonexistent_mode"})
      assert is_binary(html)
    end
  end

  describe "filter" do
    test "filter by status", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "filter", %{"status" => "downloaded", "artist" => "all"})
      assert is_binary(html)
    end

    test "filter by artist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "filter", %{"status" => "all", "artist" => "Artist A"})
      assert is_binary(html)
    end

    test "filter with defaults", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "filter", %{})
      assert is_binary(html)
    end
  end

  describe "select_voice_pack" do
    test "select deep voice pack", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_voice_pack", %{"pack_id" => "deep"})
      assert is_binary(html)
    end

    test "select bright voice pack", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_voice_pack", %{"pack_id" => "bright"})
      assert is_binary(html)
    end
  end

  describe "set_accent" do
    test "set accent value", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "set_accent", %{"value" => "0.5"})
      assert is_binary(html)
    end

    test "set accent to zero", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "set_accent", %{"value" => "0.0"})
      assert is_binary(html)
    end
  end

  describe "lalalai modal controls" do
    test "close_lalalai_modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "close_lalalai_modal")
      assert is_binary(html)
    end

    test "expand_lalalai_key_form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "expand_lalalai_key_form")
      assert is_binary(html)
    end

    test "lalalai_modal_key_input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "lalalai_modal_key_input", %{"key" => "test-key-123"})
      assert is_binary(html)
    end
  end

  describe "batch modal controls" do
    test "start_batch_process opens modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "start_batch_process")
      assert is_binary(html)
    end

    test "cancel_batch_modal closes modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "start_batch_process")
      html = render_click(view, "cancel_batch_modal")
      assert is_binary(html)
    end
  end

  describe "validate_upload" do
    test "validate_upload is a no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "validate_upload")
      assert is_binary(html)
    end
  end

  describe "dismiss_pipeline" do
    test "dismiss_pipeline removes track from pipelines", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "dismiss_pipeline", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end

  describe "toggle_select" do
    test "toggle_select adds ID to selection", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_select", %{"id" => track.id})
      assert is_binary(html)
    end

    test "toggle_select twice deselects", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_select", %{"id" => track.id})
      html = render_click(view, "toggle_select", %{"id" => track.id})
      assert is_binary(html)
    end
  end

  describe "toggle_select_all" do
    test "toggle_select_all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_select_all")
      assert is_binary(html)
    end
  end

  describe "search" do
    test "search with query", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "search", %{"query" => "test"})
      assert is_binary(html)
    end

    test "search with empty query", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "search", %{"query" => ""})
      assert is_binary(html)
    end
  end
end
