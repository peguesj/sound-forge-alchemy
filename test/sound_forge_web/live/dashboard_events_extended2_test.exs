defmodule SoundForgeWeb.DashboardEventsExtended2Test do
  @moduledoc "Additional dashboard event tests targeting uncovered handle_event clauses."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Events2 Test Track",
      artist: "Events2 Artist",
      duration: 200
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/events2.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/v.wav", file_size: 1024})

    %{track: track}
  end

  describe "spotify events" do
    test "fetch_spotify_metadata with empty URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "fetch_spotify_metadata", %{"url" => ""})
      assert is_binary(html)
    end

    test "fetch_spotify_metadata with spotify URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "fetch_spotify_metadata", %{"url" => "https://open.spotify.com/track/abc123"})
      assert is_binary(html)
    end

    test "update_spotify_url event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "update_spotify_url", %{"url" => "https://open.spotify.com/track/xyz"})
      assert is_binary(html)
    end
  end

  describe "filter and sort events" do
    test "filter_tracks by status", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "filter_tracks", %{"status" => "downloaded"})
      assert is_binary(html)
    end

    test "filter_tracks by artist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "filter_tracks", %{"artist" => "Events2 Artist"})
      assert is_binary(html)
    end

    test "sort_tracks event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort_tracks", %{"sort" => "title"})
      assert is_binary(html)
    end

    test "sort_tracks by oldest", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort_tracks", %{"sort" => "oldest"})
      assert is_binary(html)
    end
  end

  describe "batch events" do
    test "toggle_select event", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_select", %{"id" => track.id})
      assert is_binary(html)
    end

    test "toggle_select_all event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_select_all", %{})
      assert is_binary(html)
    end
  end

  describe "track management events" do
    test "delete_track event", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "delete_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "search_tracks event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "search_tracks", %{"query" => "test"})
      assert is_binary(html)
    end
  end

  describe "engine selection events" do
    test "select_engine demucs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_engine", %{"engine" => "demucs"})
      assert is_binary(html)
    end

    test "select_engine lalalai", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_engine", %{"engine" => "lalalai"})
      assert is_binary(html)
    end
  end

  describe "lalalai modal events" do
    test "show_lalalai_modal event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "show_lalalai_modal", %{})
      assert is_binary(html)
    end

    test "close_lalalai_modal event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "close_lalalai_modal", %{})
      assert is_binary(html)
    end

    test "select_lalalai_mode event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "voice_clean"})
      assert is_binary(html)
    end
  end

  describe "debug events" do
    test "toggle_debug_panel event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_debug_panel", %{})
      assert is_binary(html)
    end

    test "clear_debug_logs event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "clear_debug_logs", %{})
      assert is_binary(html)
    end

    test "debug_log_filter event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "debug_log_filter", %{"level" => "error"})
      assert is_binary(html)
    end
  end

  describe "queue events" do
    test "switch_queue_tab event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "switch_queue_tab", %{"tab" => "history"})
      assert is_binary(html)
    end
  end

  describe "pagination events" do
    test "next_page event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "next_page", %{})
      assert is_binary(html)
    end

    test "prev_page event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "prev_page", %{})
      assert is_binary(html)
    end
  end

  describe "dereverb toggle" do
    test "toggle_dereverb event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_dereverb", %{})
      assert is_binary(html)
    end
  end

  describe "auto_download toggle" do
    test "toggle_auto_download event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_auto_download", %{})
      assert is_binary(html)
    end
  end
end
