defmodule SoundForgeWeb.DashboardDebugTest do
  @moduledoc """
  Tests for DashboardLive debug panel, devtools, trace,
  queue, and MIDI log handlers.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Debug Track",
        artist: "Debug Artist",
        duration: 200
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/debug_test.mp3"
    })

    %{track: track}
  end

  describe "debug panel" do
    test "toggle_debug_panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_debug_panel", %{})
      assert is_binary(html)
    end

    test "close_debug_panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "close_debug_panel", %{})
      assert is_binary(html)
    end

    test "debug_tab overview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_tab", %{"tab" => "overview"})
      assert is_binary(html)
    end

    test "debug_tab logs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_tab", %{"tab" => "logs"})
      assert is_binary(html)
    end

    test "debug_tab midi", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_tab", %{"tab" => "midi"})
      assert is_binary(html)
    end

    test "debug_tab trace", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_tab", %{"tab" => "trace"})
      assert is_binary(html)
    end

    test "debug_tab queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_tab", %{"tab" => "queue"})
      assert is_binary(html)
    end

    test "debug_tab devtools", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_debug_panel", %{})
      html = render_click(view, "debug_tab", %{"tab" => "devtools"})
      assert is_binary(html)
    end
  end

  describe "debug log filters" do
    test "debug_log_filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "debug_log_filter", %{"level" => "error"})
      assert is_binary(html)
    end

    test "debug_log_filter_ns", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "debug_log_filter_ns", %{"namespace" => "pipeline"})
      assert is_binary(html)
    end

    test "debug_log_search", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "debug_log_search", %{"search" => "error"})
      assert is_binary(html)
    end

    test "clear_debug_logs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "clear_debug_logs", %{})
      assert is_binary(html)
    end

    test "clear_midi_log", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "clear_midi_log", %{})
      assert is_binary(html)
    end
  end

  describe "debug workers" do
    test "toggle_debug_workers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_debug_workers", %{})
      assert is_binary(html)
    end

    test "filter_logs_by_worker", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "filter_logs_by_worker", %{"worker" => "DownloadWorker"})
      assert is_binary(html)
    end
  end

  describe "debug queue" do
    test "toggle_debug_queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_debug_queue", %{})
      assert is_binary(html)
    end

    test "queue_tab active", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "queue_tab", %{"tab" => "active"})
      assert is_binary(html)
    end

    test "queue_tab history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "queue_tab", %{"tab" => "history"})
      assert is_binary(html)
    end

    test "queue_refresh_history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "queue_refresh_history", %{})
      assert is_binary(html)
    end

    test "queue_load_more", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "queue_load_more", %{})
      assert is_binary(html)
    end
  end

  describe "trace" do
    test "trace_refresh", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "trace_refresh", %{})
      assert is_binary(html)
    end
  end

  describe "devtools" do
    test "devtools_refresh", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "devtools_refresh", %{})
      assert is_binary(html)
    end

    test "devtools_flush_caches", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "devtools_flush_caches", %{})
      assert is_binary(html)
    end

    test "devtools_force_gc", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "devtools_force_gc", %{})
      assert is_binary(html)
    end

    test "devtools_reset_pipeline", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "devtools_reset_pipeline", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end
end
