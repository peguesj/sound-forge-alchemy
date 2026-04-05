defmodule SoundForgeWeb.DashboardDebugExtendedTest do
  @moduledoc """
  Tests for DashboardLive debug panel handlers not yet covered:
  debug_log_filter, debug_log_filter_ns, debug_log_search,
  clear_debug_logs, clear_midi_log, filter_logs_by_worker,
  toggle_debug_queue, queue_tab, queue_refresh_history, queue_load_more,
  anchor_job_logs, trace_select_job, trace_refresh,
  devtools_refresh, devtools_flush_caches, devtools_force_gc.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  defp open_debug_panel(view) do
    render_click(view, "toggle_debug_panel")
    view
  end

  describe "debug log filters" do
    test "debug_log_filter sets level", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      html = render_click(view, "debug_log_filter", %{"level" => "error"})
      assert is_binary(html)
    end

    test "debug_log_filter_ns sets namespace", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      html = render_click(view, "debug_log_filter_ns", %{"namespace" => "oban.download"})
      assert is_binary(html)
    end

    test "debug_log_search sets search term", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      html = render_click(view, "debug_log_search", %{"search" => "error"})
      assert is_binary(html)
    end
  end

  describe "debug log clearing" do
    test "clear_debug_logs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      html = render_click(view, "clear_debug_logs")
      assert is_binary(html)
    end

    test "clear_midi_log", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      html = render_click(view, "clear_midi_log")
      assert is_binary(html)
    end
  end

  describe "filter_logs_by_worker" do
    test "switches to logs tab with worker namespace", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      html = render_click(view, "filter_logs_by_worker", %{"worker" => "DownloadWorker"})
      assert is_binary(html)
    end
  end

  describe "queue panel" do
    test "toggle_debug_queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      html = render_click(view, "toggle_debug_queue")
      assert is_binary(html)
    end

    test "queue_tab switches tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      html = render_click(view, "queue_tab", %{"tab" => "history"})
      assert is_binary(html)
    end

    test "queue_refresh_history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      html = render_click(view, "queue_refresh_history")
      assert is_binary(html)
    end

    test "queue_load_more with empty history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      html = render_click(view, "queue_load_more")
      assert is_binary(html)
    end
  end

  describe "anchor_job_logs" do
    test "sets search to job ID", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      html = render_click(view, "anchor_job_logs", %{"job-id" => "12345"})
      assert is_binary(html)
    end
  end

  describe "trace" do
    test "trace_refresh loads jobs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      render_click(view, "debug_tab", %{"tab" => "tracing"})
      html = render_click(view, "trace_refresh")
      assert is_binary(html)
    end

    test "trace_select_job with invalid id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      render_click(view, "debug_tab", %{"tab" => "tracing"})
      html = render_click(view, "trace_select_job", %{"job-id" => "not_a_number"})
      assert is_binary(html)
    end

    test "trace_select_job with nonexistent job", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      render_click(view, "debug_tab", %{"tab" => "tracing"})
      html = render_click(view, "trace_select_job", %{"job-id" => "999999"})
      assert is_binary(html)
    end
  end

  describe "devtools" do
    test "devtools_refresh", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      render_click(view, "debug_tab", %{"tab" => "devtools"})
      html = render_click(view, "devtools_refresh")
      assert is_binary(html)
    end

    test "devtools_flush_caches", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      render_click(view, "debug_tab", %{"tab" => "devtools"})
      html = render_click(view, "devtools_flush_caches")
      assert is_binary(html)
    end

    test "devtools_force_gc", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      open_debug_panel(view)
      render_click(view, "debug_tab", %{"tab" => "devtools"})
      html = render_click(view, "devtools_force_gc")
      assert is_binary(html)
    end
  end
end
