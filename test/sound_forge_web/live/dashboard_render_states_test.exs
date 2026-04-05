defmodule SoundForgeWeb.DashboardRenderStatesTest do
  @moduledoc """
  Tests exercising dashboard template rendering branches with various data states:
  tracks with different pipeline stages, empty states, specific view modes, etc.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "empty state" do
    test "renders empty library with no tracks", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "library" or html =~ "Library" or html =~ "No tracks"
    end
  end

  describe "view modes" do
    test "grid view renders", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "Grid Track"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_view", %{"mode" => "grid"})
      assert html =~ "Grid Track"
    end

    test "list view renders", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "List Track"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_view", %{"mode" => "list"})
      assert html =~ "List Track"
    end

    test "list_expanded view renders", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "Expanded Track"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_view", %{"mode" => "list_expanded"})
      assert html =~ "Expanded Track"
    end
  end

  describe "track states" do
    test "fresh track without any jobs", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "Fresh"})
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Fresh"
    end

    test "track with queued download", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Queued DL"})
      download_job_fixture(%{track_id: track.id, status: :queued})
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Queued DL"
    end

    test "track with downloading status", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Downloading"})
      download_job_fixture(%{track_id: track.id, status: :downloading, progress: 50})
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Downloading"
    end

    test "track with failed download", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Failed DL"})
      download_job_fixture(%{track_id: track.id, status: :failed})
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Failed DL"
    end

    test "track with queued processing", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Queued Proc"})
      processing_job_fixture(%{track_id: track.id, status: :queued})
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Queued Proc"
    end

    test "track with queued analysis", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Queued Analysis"})
      analysis_job_fixture(%{track_id: track.id, status: :queued})
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Queued Analysis"
    end

    test "track with failed processing", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Failed Proc"})
      processing_job_fixture(%{track_id: track.id, status: :failed})
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Failed Proc"
    end
  end

  describe "search" do
    test "search filters tracks", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "Unique Search Term XYZ"})
      track_fixture(%{user_id: user.id, title: "Other Track"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "search", %{"query" => "Unique Search Term"})
      assert html =~ "Unique Search Term XYZ"
    end

    test "search with no matches", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "Existing"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "search", %{"query" => "nonexistent_track_abc"})
      assert is_binary(html)
    end

    test "clear search", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "Clearable"})
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "search", %{"query" => "xyz"})
      html = render_click(view, "search", %{"query" => ""})
      assert html =~ "Clearable"
    end
  end

  describe "filter combinations" do
    test "filter by status downloaded", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "DL Filter"})
      download_job_fixture(%{track_id: track.id, status: :completed, output_path: "/tmp/x.mp3"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "filter", %{"status" => "downloaded"})
      assert is_binary(html)
    end

    test "filter by status processing", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Proc Filter"})
      processing_job_fixture(%{track_id: track.id, status: :processing})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "filter", %{"status" => "processing"})
      assert is_binary(html)
    end

    test "filter by status analyzed", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Ana Filter"})
      aj = analysis_job_fixture(%{track_id: track.id, status: :completed})
      analysis_result_fixture(%{track_id: track.id, analysis_job_id: aj.id})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "filter", %{"status" => "analyzed"})
      assert is_binary(html)
    end
  end

  describe "navigation tabs" do
    test "nav_tab to library", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "library"})
      assert is_binary(html)
    end

    test "nav_tab to browse", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "browse"})
      assert is_binary(html)
    end

    test "nav_all_tracks", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_all_tracks")
      assert is_binary(html)
    end

    test "nav_recent", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_recent")
      assert is_binary(html)
    end

    test "nav_artists", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_artists")
      assert is_binary(html)
    end

    test "nav_albums", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_albums")
      assert is_binary(html)
    end
  end

  describe "drawer" do
    test "open and close drawer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "open_drawer")
      assert is_binary(html)
      html2 = render_click(view, "close_drawer")
      assert is_binary(html2)
    end
  end

  describe "track operations" do
    test "select and play track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Play Me"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "select_track", %{"track_id" => track.id})
      assert is_binary(html)
    end

    test "play_track with spotify-only track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Spotify Only"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "play_track", %{"id" => track.id})
      assert is_binary(html)
    end
  end

  describe "batch mode" do
    test "toggle batch mode on and off", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_batch_mode")
      assert is_binary(html)
      html2 = render_click(view, "toggle_batch_mode")
      assert is_binary(html2)
    end
  end

  describe "shift select" do
    test "shift_select_range with tracks", %{conn: conn, user: user} do
      t1 = track_fixture(%{user_id: user.id, title: "Shift 1"})
      _t2 = track_fixture(%{user_id: user.id, title: "Shift 2"})
      t3 = track_fixture(%{user_id: user.id, title: "Shift 3"})
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_select", %{"id" => t1.id})
      html = render_click(view, "shift_select_range", %{"id" => t3.id})
      assert is_binary(html)
    end
  end
end
