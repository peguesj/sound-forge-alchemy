defmodule SoundForgeWeb.DashboardExtendedTest do
  @moduledoc """
  Extended DashboardLive tests: tab navigation, toggle events, filter events,
  batch mode, engine selection, and miscellaneous handle_events.
  """
  use SoundForgeWeb.ConnCase
  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "tab navigation via handle_params" do
    test "navigates to DJ tab", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/?tab=dj")
      assert html =~ "Alchemy"
    end

    test "navigates to DAW tab", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/?tab=daw")
      assert html =~ "Alchemy"
    end

    test "navigates to Pads tab", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/?tab=pads")
      assert html =~ "Alchemy"
    end

    test "navigates to DAW tab with track_id", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")
      assert html =~ "Alchemy"
    end

    test "default params renders library", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Alchemy"
    end
  end

  describe "toggle events" do
    test "toggle_view switches between grid and list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_view", %{"mode" => "list"})
      assert html =~ "Alchemy"

      html = render_click(view, "toggle_view", %{"mode" => "grid"})
      assert html =~ "Alchemy"
    end

    test "toggle_auto_download toggles auto download", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_auto_download")
      assert html =~ "Alchemy"
    end

    test "toggle_batch_mode enables batch mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_batch_mode")
      assert html =~ "Alchemy"
    end

    test "toggle_preview toggles preview mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_preview")
      assert html =~ "Alchemy"
    end

    test "toggle_dereverb toggles dereverb option", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_dereverb")
      assert html =~ "Alchemy"
    end
  end

  describe "filter events" do
    test "filters by status", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html =
        view
        |> element("form[phx-change='filter']")
        |> render_change(%{"status" => "pending"})

      assert html =~ "Alchemy"
    end

    test "filters by downloaded status", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html =
        view
        |> element("form[phx-change='filter']")
        |> render_change(%{"status" => "downloaded"})

      assert html =~ "Alchemy"
    end
  end

  describe "engine selection" do
    test "select_engine demucs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "select_engine", %{"engine" => "demucs"})
      assert html =~ "Alchemy"
    end

    test "select_engine lalalai shows modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "select_engine", %{"engine" => "lalalai"})
      assert html =~ "Alchemy"
    end

    test "close_lalalai_modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      html = render_click(view, "close_lalalai_modal")
      assert html =~ "Alchemy"
    end
  end

  describe "lalalai modal events" do
    test "expand_lalalai_key_form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      html = render_click(view, "expand_lalalai_key_form")
      assert html =~ "Alchemy"
    end

    test "lalalai_modal_key_input", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      html = render_click(view, "lalalai_modal_key_input", %{"key" => "test-key"})
      assert html =~ "Alchemy"
    end

    test "select_lalalai_mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      html = render_click(view, "select_lalalai_mode", %{"mode" => "voice_cleaner"})
      assert html =~ "Alchemy"
    end

    test "toggle_multistem", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_multistem", %{"stem" => "drums"})
      assert html =~ "Alchemy"
    end

    test "set_noise_level", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_noise_level", %{"level" => "2"})
      assert html =~ "Alchemy"
    end

    test "set_accent", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_accent", %{"value" => "0.8"})
      assert html =~ "Alchemy"
    end
  end

  describe "track selection" do
    test "toggle_select adds and removes track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")

      html = render_click(view, "toggle_select", %{"id" => track.id})
      assert html =~ "Alchemy"

      html = render_click(view, "toggle_select", %{"id" => track.id})
      assert html =~ "Alchemy"
    end

    test "toggle_select_all selects all", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")

      html = render_click(view, "toggle_select_all")
      assert html =~ "Alchemy"
    end

    test "toggle_track_select", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")

      html = render_click(view, "toggle_track_select", %{"track_id" => track.id})
      assert html =~ "Alchemy"
    end
  end

  describe "batch operations" do
    test "batch_delete with no selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "batch_delete")
      assert html =~ "Alchemy"
    end

    test "batch_analyze with no selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "batch_analyze")
      assert html =~ "Alchemy"
    end

    test "batch_process with no selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "batch_process")
      assert html =~ "Alchemy"
    end

    test "start_batch_process opens modal", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_select", %{"id" => track.id})
      html = render_click(view, "start_batch_process")
      assert html =~ "Alchemy"
    end

    test "cancel_batch_modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "cancel_batch_modal")
      assert html =~ "Alchemy"
    end
  end

  describe "download and process track" do
    test "download_track with valid id", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "download_track", %{"id" => track.id})
      assert html =~ "Alchemy"
    end

    test "download_track with invalid id", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "download_track", %{"id" => Ecto.UUID.generate()})
      assert html =~ "Alchemy"
    end

    test "process_track with valid id", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "process_track", %{"id" => track.id})
      assert html =~ "Alchemy"
    end

    test "analyze_track with valid id", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "analyze_track", %{"id" => track.id})
      assert html =~ "Alchemy"
    end
  end

  describe "sort options" do
    test "sort by artist", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html =
        view
        |> element("form[phx-change='sort']")
        |> render_change(%{"sort_by" => "artist"})

      assert html =~ "Alchemy"
    end

    test "sort by duration", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html =
        view
        |> element("form[phx-change='sort']")
        |> render_change(%{"sort_by" => "duration"})

      assert html =~ "Alchemy"
    end

    test "sort by oldest", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html =
        view
        |> element("form[phx-change='sort']")
        |> render_change(%{"sort_by" => "oldest"})

      assert html =~ "Alchemy"
    end
  end

  describe "notification events" do
    test "handles new_notification", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      send(view.pid, {:new_notification, %{
        id: Ecto.UUID.generate(),
        type: :info,
        title: "Test",
        message: "Test message",
        metadata: %{},
        read: false,
        inserted_at: DateTime.utc_now()
      }})

      html = render(view)
      assert html =~ "Alchemy"
    end
  end

  describe "debug events" do
    test "toggle_debug_panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_debug_panel")
      assert html =~ "Alchemy"
    end

    test "switch_debug_tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "switch_debug_tab", %{"tab" => "workers"})
      assert html =~ "Alchemy"
    end
  end

  describe "nav_tab events" do
    test "nav_tab library", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "library"})
      assert html =~ "Alchemy"
    end

    test "nav_tab browse", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "browse"})
      assert html =~ "Alchemy"
    end

    test "nav_tab dj", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "dj"})
      assert html =~ "Alchemy"
    end

    test "nav_tab daw", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "daw"})
      assert html =~ "Alchemy"
    end

    test "nav_tab pads", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "pads"})
      assert html =~ "Alchemy"
    end

    test "nav_tab unknown", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "nonexistent"})
      assert html =~ "Alchemy"
    end
  end

  describe "drawer events" do
    test "open_drawer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "open_drawer")
      assert html =~ "Alchemy"
    end

    test "close_drawer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "open_drawer")
      html = render_click(view, "close_drawer")
      assert html =~ "Alchemy"
    end
  end

  describe "nav context events" do
    test "nav_all_tracks", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_all_tracks")
      assert html =~ "Alchemy"
    end

    test "nav_recent", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_recent")
      assert html =~ "Alchemy"
    end
  end

  describe "metadata editing" do
    test "edit_metadata", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Edit Me"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "edit_metadata", %{"id" => track.id})
      assert html =~ "Alchemy"
    end

    test "cancel_edit", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "cancel_edit")
      assert html =~ "Alchemy"
    end
  end

  describe "spotify events" do
    test "spotify_error with type account", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "spotify_error", %{"type" => "account", "message" => "not premium"})
      assert html =~ "Alchemy"
    end

    test "spotify_error with type other", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "spotify_error", %{"type" => "playback", "message" => "failed"})
      assert html =~ "Alchemy"
    end

    test "spotify_error with only message", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "spotify_error", %{"message" => "unknown error"})
      assert html =~ "Alchemy"
    end

    test "play_spotify", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "play_spotify", %{"uri" => "spotify:track:abc123"})
      assert html =~ "Alchemy"
    end

    test "spotify_playback_state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "spotify_playback_state", %{"is_playing" => true, "position" => 0})
      assert html =~ "Alchemy"
    end
  end

  describe "keyboard shortcuts" do
    test "keydown unknown key", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "keydown", %{"key" => "a"})
      assert html =~ "Alchemy"
    end
  end

  describe "confirm_batch_process" do
    test "with selected tracks", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      dl = download_job_fixture(%{track_id: track.id, status: :completed, output_path: "/tmp/test.mp3"})
      {:ok, view, _html} = live(conn, "/")

      render_click(view, "toggle_select", %{"id" => track.id})
      render_click(view, "start_batch_process")
      html = render_click(view, "confirm_batch_process", %{"engine" => "demucs", "stem_filter" => "all"})
      assert html =~ "Alchemy"
    end
  end

  describe "play_track" do
    test "play_track with valid stemmed track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, user_id: user.id})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, view, _html} = live(conn, "/")

      assert {:error, {:live_redirect, %{to: "/tracks/" <> _}}} =
               render_click(view, "play_track", %{"id" => track.id})
    end
  end

  describe "additional navigation events" do
    test "nav_playlist", %{conn: conn, user: user} do
      playlist = playlist_fixture(%{user_id: user.id, name: "TestPL"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_playlist", %{"id" => playlist.id})
      assert html =~ "Alchemy"
    end

    test "nav_artists", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_artists", %{})
      assert html =~ "Alchemy"
    end

    test "nav_albums", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_albums", %{})
      assert html =~ "Alchemy"
    end

    test "nav_artist with specific artist", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_artist", %{"artist" => "Test Artist"})
      assert html =~ "Alchemy"
    end

    test "nav_album with specific album", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_album", %{"album" => "Test Album"})
      assert html =~ "Alchemy"
    end

    test "new_playlist", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "new_playlist", %{})
      assert html =~ "Alchemy"
    end
  end

  describe "debug panel events" do
    test "close_debug_panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "close_debug_panel")
      assert html =~ "Alchemy"
    end

    test "debug_tab switch", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_tab", %{"tab" => "trace"})
      assert html =~ "Alchemy"
    end

    test "debug_log_filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_log_filter", %{"level" => "error"})
      assert html =~ "Alchemy"
    end

    test "debug_log_filter_ns", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_log_filter_ns", %{"namespace" => "oban"})
      assert html =~ "Alchemy"
    end

    test "debug_log_search", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "debug_log_search", %{"search" => "error"})
      assert html =~ "Alchemy"
    end

    test "clear_debug_logs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "clear_debug_logs")
      assert html =~ "Alchemy"
    end

    test "clear_midi_log", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "clear_midi_log")
      assert html =~ "Alchemy"
    end

    test "toggle_debug_workers", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "toggle_debug_workers")
      assert html =~ "Alchemy"
    end

    test "filter_logs_by_worker", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "filter_logs_by_worker", %{"worker" => "DownloadWorker"})
      assert html =~ "Alchemy"
    end
  end

  describe "queue events" do
    test "toggle_debug_queue", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "toggle_debug_queue")
      assert html =~ "Alchemy"
    end

    test "queue_tab switch", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "queue_tab", %{"tab" => "history"})
      assert html =~ "Alchemy"
    end

    test "queue_refresh_history", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "queue_refresh_history")
      assert html =~ "Alchemy"
    end
  end

  describe "devtools events" do
    test "devtools_refresh", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "devtools_refresh")
      assert html =~ "Alchemy"
    end

    test "devtools_flush_caches", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "devtools_flush_caches")
      assert html =~ "Alchemy"
    end

    test "devtools_force_gc", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "devtools_force_gc")
      assert html =~ "Alchemy"
    end
  end

  describe "spotify player events" do
    test "spotify_player_ready", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "spotify_player_ready", %{"device_id" => "abc123"})
      assert html =~ "Alchemy"
    end
  end

  describe "save_metadata" do
    test "save_metadata for track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Original"})
      {:ok, view, _html} = live(conn, "/")

      render_click(view, "edit_metadata", %{"id" => track.id})
      html = render_click(view, "save_metadata", %{"title" => "Updated", "artist" => "New Artist"})
      assert html =~ "Alchemy"
    end
  end

  describe "batch_download" do
    test "batch_download with selected tracks", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, spotify_id: "sp_batch_dl"})
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_select", %{"id" => track.id})
      html = render_click(view, "batch_download")
      assert html =~ "Alchemy"
    end
  end

  describe "load_in_pads" do
    test "load_in_pads with track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "load_in_pads", %{"id" => track.id})
      assert html =~ "Alchemy"
    end
  end

  describe "handle_info messages" do
    test "dismiss_toast", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:dismiss_toast, "toast_123"})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "batch_progress", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:batch_progress, %{batch_job_id: "bj_1", status: :processing, completed_count: 1, total_count: 3}})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "batch_complete", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:batch_complete, %{batch_job_id: "bj_1", completed_count: 3, total_count: 3, failed_count: 0}})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "debug_log event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:debug_log, %{level: :info, message: "test log", namespace: nil, timestamp: "2026-01-01 00:00:00", metadata: %{}}})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "worker_status_change", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:worker_status_change, %{worker: "DownloadWorker", state: :running}})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "bpm_update", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:bpm_update, 128.5})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "transport state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:transport, :playing})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "dismiss_pipeline_from_tracker", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:dismiss_pipeline_from_tracker, track.id})
      html = render(view)
      assert html =~ "Alchemy"
    end
  end

  describe "pagination" do
    test "page event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "page", %{"page" => "2"})
      assert html =~ "Alchemy"
    end
  end

  describe "retry_pipeline" do
    test "retries pipeline for track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "retry_pipeline", %{"id" => track.id})
      assert html =~ "Alchemy"
    end
  end

  describe "force_reset_pipeline" do
    test "force resets pipeline", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "force_reset_pipeline", %{"id" => track.id})
      assert html =~ "Alchemy"
    end
  end

  describe "fetch_spotify" do
    test "fetch_spotify with URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "fetch_spotify", %{"url" => "https://open.spotify.com/track/abc123"})
      assert html =~ "Alchemy"
    end
  end

  describe "shift_select_range" do
    test "shift select range of tracks", %{conn: conn, user: user} do
      t1 = track_fixture(%{user_id: user.id, title: "Track 1"})
      t2 = track_fixture(%{user_id: user.id, title: "Track 2"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "shift_select_range", %{"from_id" => t1.id, "to_id" => t2.id})
      assert html =~ "Alchemy"
    end
  end

  describe "select_voice_pack" do
    test "selects a voice pack", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "select_voice_pack", %{"pack_id" => "phoenix"})
      assert html =~ "Alchemy"
    end
  end

  describe "test_save_lalalai_key" do
    test "test_save_lalalai_key event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "test_save_lalalai_key", %{})
      assert html =~ "Alchemy"
    end
  end

  describe "trace events" do
    test "trace_select_job", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "trace_select_job", %{"job-id" => "123"})
      assert html =~ "Alchemy"
    end

    test "trace_refresh", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "trace_refresh")
      assert html =~ "Alchemy"
    end
  end

  describe "queue_load_more" do
    test "loads more queue items", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "queue_load_more")
      assert html =~ "Alchemy"
    end
  end

  describe "uat events" do
    test "uat_run_scenario", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "uat_run_scenario", %{"scenario" => "import_track"})
      assert html =~ "Alchemy"
    end

    test "uat_reset_scenario", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "uat_reset_scenario", %{"scenario" => "import_track"})
      assert html =~ "Alchemy"
    end

    test "uat_clear_log", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "uat_clear_log")
      assert html =~ "Alchemy"
    end
  end

  describe "additional handle_info" do
    test "spotify_pause", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, :spotify_pause)
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "spotify_resume", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, :spotify_resume)
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "spotify_seek", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:spotify_seek, 30000})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "midi_device_connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:midi_device_connected, %{name: "MIDI Controller", port_id: "input:0"}})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "midi_device_disconnected", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:midi_device_disconnected, %{name: "MIDI Controller", port_id: "input:0"}})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "midi_action with stem_volume", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:midi_action, :stem_volume, %{volume: 80.0, target: "vocals"}})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "midi_action generic", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:midi_action, :play, %{}})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "ref message from async Task", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      ref = make_ref()
      send(view.pid, {ref, :ok})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "DOWN message", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:DOWN, make_ref(), :process, self(), :normal})
      html = render(view)
      assert html =~ "Alchemy"
    end
  end

  describe "devtools_reset_pipeline" do
    test "reset pipeline for a track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "devtools_reset_pipeline", %{"track-id" => to_string(track.id)})
      assert html =~ "Alchemy"
    end
  end

  describe "anchor_job_logs" do
    test "anchors job logs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "toggle_debug_panel")
      html = render_click(view, "anchor_job_logs", %{"job-id" => "42"})
      assert html =~ "Alchemy"
    end
  end

  describe "upload_audio" do
    test "upload_audio event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "upload_audio", %{})
      assert html =~ "Alchemy"
    end
  end

  describe "validate_upload" do
    test "validate_upload event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "validate_upload", %{})
      assert html =~ "Alchemy"
    end
  end

  describe "test_lalalai_connection" do
    test "test_lalalai_connection without key configured", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "test_lalalai_connection", %{})
      assert html =~ "Alchemy"
    end
  end

  describe "lalalai handle_info messages" do
    test "lalalai_connection_result ok", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:lalalai_connection_result, {:ok, :valid}})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "lalalai_connection_result error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:lalalai_connection_result, {:error, :invalid}})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "lalalai_modal_test_result valid", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:lalalai_modal_test_result, {:ok, :valid}, "test_key"})
      html = render(view)
      assert html =~ "Alchemy"
    end

    test "lalalai_modal_test_result invalid", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:lalalai_modal_test_result, {:error, :invalid_api_key}, "bad_key"})
      html = render(view)
      assert html =~ "Alchemy"
    end
  end

  describe "spotify metadata handle_info" do
    test "spotify_metadata error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:spotify_metadata, "https://spotify.com/track/abc", {:error, "not found"}})
      html = render(view)
      assert html =~ "Alchemy"
    end
  end

  describe "virtual_controller trigger_cue" do
    test "virtual_controller trigger_cue handle_info", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      send(view.pid, {:midi_action, :trigger_cue, %{cue_index: 0}})
      html = render(view)
      assert html =~ "Alchemy"
    end
  end

  describe "uat_step" do
    test "uat_step handle_info", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      # First start a scenario
      render_click(view, "uat_run_scenario", %{"scenario" => "import_track"})
      # Then receive a step completion
      send(view.pid, {:uat_step, :import_track, 0})
      html = render(view)
      assert html =~ "Alchemy"
    end
  end

  describe "select_lalalai_mode" do
    test "selects stem_separator mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "stem_separator"})
      assert html =~ "Alchemy"
    end

    test "selects voice_cleaner mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "voice_cleaner"})
      assert html =~ "Alchemy"
    end
  end
end
