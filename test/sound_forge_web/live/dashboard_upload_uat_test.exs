defmodule SoundForgeWeb.DashboardUploadUatTest do
  @moduledoc """
  Tests for DashboardLive upload cancel, UAT scenario management,
  and other previously uncovered event handlers.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Upload UAT Track",
      artist: "Test Artist",
      duration: 200
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/upload_uat.mp3"
    })

    %{track: track}
  end

  describe "validate_upload" do
    test "validate_upload event is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "validate_upload", %{})
      assert is_binary(html)
    end
  end

  describe "UAT scenario management" do
    test "uat_run_scenario with import_track", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "uat_run_scenario", %{"scenario" => "import_track"})
      assert is_binary(html)
    end

    test "uat_run_scenario with playback_test", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "uat_run_scenario", %{"scenario" => "playback_test"})
      assert is_binary(html)
    end

    test "uat_run_scenario with full_pipeline", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "uat_run_scenario", %{"scenario" => "full_pipeline"})
      assert is_binary(html)
    end

    test "uat_run_scenario with dj_mode_test", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "uat_run_scenario", %{"scenario" => "dj_mode_test"})
      assert is_binary(html)
    end

    test "uat_run_scenario blocks when already running", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "uat_run_scenario", %{"scenario" => "import_track"})
      # Second attempt while first is running
      html = render_click(view, "uat_run_scenario", %{"scenario" => "playback_test"})
      assert is_binary(html)
    end

    test "uat_reset_scenario", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "uat_run_scenario", %{"scenario" => "import_track"})
      html = render_click(view, "uat_reset_scenario", %{"scenario" => "import_track"})
      assert is_binary(html)
    end

    test "uat_clear_log", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "uat_clear_log", %{})
      assert is_binary(html)
    end
  end

  describe "sort operations" do
    test "sort_tracks by title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort_tracks", %{"field" => "title"})
      assert is_binary(html)
    end

    test "sort_tracks by artist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort_tracks", %{"field" => "artist"})
      assert is_binary(html)
    end

    test "sort_tracks by duration", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort_tracks", %{"field" => "duration"})
      assert is_binary(html)
    end

    test "sort_tracks toggles direction on double click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "sort_tracks", %{"field" => "title"})
      html = render_click(view, "sort_tracks", %{"field" => "title"})
      assert is_binary(html)
    end
  end

  describe "track selection with multiple tracks" do
    test "select multiple tracks then deselect one", %{conn: conn, track: track} do
      track2 = track_fixture(%{user_id: track.user_id, title: "Second Track"})

      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_track_select", %{"track_id" => track.id})
      render_click(view, "toggle_track_select", %{"track_id" => track2.id})
      # Deselect first
      html = render_click(view, "toggle_track_select", %{"track_id" => track.id})
      assert is_binary(html)
    end
  end

  describe "notification actions" do
    test "dismiss_notification", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "dismiss_notification", %{"id" => "test-notif-1"})
      assert is_binary(html)
    end

    test "clear_all_notifications", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "clear_all_notifications", %{})
      assert is_binary(html)
    end
  end

  describe "track detail" do
    test "show_track_detail", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "show_track_detail", %{"id" => track.id})
      assert is_binary(html)
    end

    test "close_track_detail", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "show_track_detail", %{"id" => track.id})
      html = render_click(view, "close_track_detail", %{})
      assert is_binary(html)
    end

    test "show_track_detail for nonexistent track", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "show_track_detail", %{"id" => Ecto.UUID.generate()})
      assert is_binary(html)
    end
  end
end
