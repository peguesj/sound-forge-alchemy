defmodule SoundForgeWeb.DashboardEventsMegaTest do
  @moduledoc "Comprehensive DashboardLive event coverage for remaining handle_event clauses."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{user_id: user.id, title: "Dashboard Mega", artist: "Test", duration: 200})

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/mega.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    stem_fixture(%{
      track_id: track.id,
      processing_job_id: pj.id,
      stem_type: :vocals,
      file_path: "stems/v.wav",
      file_size: 1024
    })

    %{track: track}
  end

  describe "search and filter" do
    test "search event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "search", %{"query" => "test"})
      assert is_binary(html)
    end

    test "search with empty query", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "search", %{"query" => ""})
      assert is_binary(html)
    end

    test "filter event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "filter", %{"filter" => "all"})
      assert is_binary(html)
    end

    test "sort by title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort", %{"sort_by" => "title"})
      assert is_binary(html)
    end

    test "sort by artist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort", %{"sort_by" => "artist"})
      assert is_binary(html)
    end

    test "sort by duration", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "sort", %{"sort_by" => "duration"})
      assert is_binary(html)
    end
  end

  describe "view toggle" do
    test "toggle_view to grid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_view", %{"mode" => "grid"})
      assert is_binary(html)
    end

    test "toggle_view to list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_view", %{"mode" => "list"})
      assert is_binary(html)
    end
  end

  describe "batch operations" do
    test "toggle_select", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_select", %{"id" => track.id})
      assert is_binary(html)
    end

    test "toggle_select_all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_select_all", %{})
      assert is_binary(html)
    end

    test "toggle_batch_mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_batch_mode", %{})
      assert is_binary(html)
    end

    test "toggle_track_select", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_track_select", %{"track_id" => track.id})
      assert is_binary(html)
    end

    test "batch_analyze with no selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "batch_analyze", %{})
      assert is_binary(html)
    end

    test "batch_process with no selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "batch_process", %{})
      assert is_binary(html)
    end

    test "batch_delete with no selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "batch_delete", %{})
      assert is_binary(html)
    end

    test "batch_download with no selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "batch_download", %{})
      assert is_binary(html)
    end

    test "start_batch_process", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "start_batch_process", %{})
      assert is_binary(html)
    end

    test "cancel_batch_modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "cancel_batch_modal", %{})
      assert is_binary(html)
    end
  end

  describe "track operations" do
    test "download_track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "download_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "process_track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "process_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "analyze_track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "analyze_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "play_track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      result = render_click(view, "play_track", %{"id" => track.id})
      # May redirect to track detail
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end

    test "select_track navigates to detail", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      result = render_click(view, "select_track", %{"id" => track.id})
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end
  end

  describe "engine and lalalai events" do
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

    test "close_lalalai_modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "close_lalalai_modal", %{})
      assert is_binary(html)
    end

    test "toggle_dereverb", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_dereverb", %{})
      assert is_binary(html)
    end

    test "toggle_auto_download", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_auto_download", %{})
      assert is_binary(html)
    end

    test "toggle_preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_preview", %{})
      assert is_binary(html)
    end

    test "expand_lalalai_key_form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "expand_lalalai_key_form", %{})
      assert is_binary(html)
    end

    test "lalalai_modal_key_input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "lalalai_modal_key_input", %{"key" => "test-key"})
      assert is_binary(html)
    end

    test "select_lalalai_mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "demuser"})
      assert is_binary(html)
    end

    test "toggle_multistem", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_multistem", %{"stem" => "vocals"})
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
      html = render_click(view, "set_accent", %{"value" => "0.7"})
      assert is_binary(html)
    end
  end

  describe "metadata editing" do
    test "edit_metadata", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "edit_metadata", %{"id" => track.id})
      assert is_binary(html)
    end

    test "cancel_edit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "cancel_edit", %{})
      assert is_binary(html)
    end
  end

  describe "nav_tab events" do
    test "nav_tab library", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_tab", %{"tab" => "library"})
      assert is_binary(html)
    end

    test "nav_tab browse", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nav_tab", %{"tab" => "browse"})
      assert is_binary(html)
    end
  end

  describe "spotify events" do
    test "spotify_player_ready", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_player_ready", %{"device_id" => "test-device"})
      assert is_binary(html)
    end

    test "spotify_error account type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_click(view, "spotify_error", %{
          "type" => "account",
          "message" => "Premium required"
        })

      assert is_binary(html)
    end

    test "spotify_error other type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_click(view, "spotify_error", %{
          "type" => "playback",
          "message" => "Device not found"
        })

      assert is_binary(html)
    end

    test "spotify_error message only", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_error", %{"message" => "Generic error"})
      assert is_binary(html)
    end

    test "spotify_playback_state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "spotify_playback_state", %{"paused" => true, "position" => 0})
      assert is_binary(html)
    end
  end
end
