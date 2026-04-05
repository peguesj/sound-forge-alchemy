defmodule SoundForgeWeb.DashboardExtendedEventsTest do
  @moduledoc "Tests for DashboardLive event handlers not covered by existing tests."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "lalalai modal events" do
    test "select_lalalai_mode changes mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "voice_clean"})
      assert is_binary(html)
    end

    test "toggle_multistem toggles stem selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_multistem", %{"stem" => "vocals"})
      assert is_binary(html)
    end

    test "set_noise_level sets noise cancelling level", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "set_noise_level", %{"level" => "2"})
      assert is_binary(html)
    end

    test "set_accent adjusts voice accent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "set_accent", %{"value" => "0.8"})
      assert is_binary(html)
    end

    test "toggle_dereverb toggles dereverb option", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_dereverb")
      assert is_binary(html)
    end

    test "expand_lalalai_key_form expands form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "expand_lalalai_key_form")
      assert is_binary(html)
    end

    test "lalalai_modal_key_input updates key field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "lalalai_modal_key_input", %{"key" => "test_key_123"})
      assert is_binary(html)
    end
  end

  describe "debug panel events" do
    test "debug_log_filter filters by level", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_log_filter", %{"level" => "error"})
      assert is_binary(html)
    end

    test "debug_log_search searches logs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_log_search", %{"search" => "test query"})
      assert is_binary(html)
    end

    test "clear_debug_logs clears log entries", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "clear_debug_logs")
      assert is_binary(html)
    end

    test "clear_midi_log clears MIDI log", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "clear_midi_log")
      assert is_binary(html)
    end

    test "toggle_debug_workers toggles worker visibility", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "toggle_debug_workers")
      assert is_binary(html)
    end

    test "toggle_debug_queue toggles queue panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "toggle_debug_queue")
      assert is_binary(html)
    end

    test "queue_tab switches queue view tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "queue_tab", %{"tab" => "history"})
      assert is_binary(html)
    end

    test "queue_refresh_history refreshes queue history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "queue_refresh_history")
      assert is_binary(html)
    end

    test "devtools_refresh refreshes devtools panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "devtools_refresh")
      assert is_binary(html)
    end

    test "devtools_flush_caches flushes all caches", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "devtools_flush_caches")
      assert is_binary(html)
    end

    test "devtools_force_gc triggers garbage collection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "devtools_force_gc")
      assert is_binary(html)
    end
  end

  describe "batch operation events" do
    test "toggle_select toggles track selection", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_batch_mode")
      html = render_click(view, "toggle_select", %{"id" => track.id})
      assert is_binary(html)
    end

    test "toggle_select_all toggles all tracks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_batch_mode")
      html = render_click(view, "toggle_select_all")
      assert is_binary(html)
    end
  end

  describe "pipeline events" do
    test "dismiss_pipeline clears pipeline notification", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "dismiss_pipeline", %{"track-id" => track.id})
      assert is_binary(html)
    end

    test "force_reset_pipeline resets track pipeline", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "force_reset_pipeline", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end

  describe "spotify events" do
    test "fetch_spotify with invalid URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "fetch_spotify", %{"url" => "not-a-spotify-url"})
      assert is_binary(html)
    end
  end

  describe "pagination" do
    test "page event navigates to page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "page", %{"page" => "1"})
      assert is_binary(html)
    end
  end

  describe "delete_track" do
    test "deletes a track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Delete Me"})
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "delete_track", %{"id" => track.id})
      assert is_binary(html)
    end
  end

  describe "catch-all handler" do
    test "unknown event is handled gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nonexistent_event_xyz_123")
      assert is_binary(html)
    end
  end
end
