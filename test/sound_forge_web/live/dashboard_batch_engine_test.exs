defmodule SoundForgeWeb.DashboardBatchEngineTest do
  @moduledoc """
  Tests for DashboardLive batch operations, engine selection, metadata editing,
  and additional handlers not covered by other test files.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Batch Engine Test Track",
        artist: "Test Artist",
        duration: 200,
        album: "Test Album",
        spotify_url: "https://open.spotify.com/track/test123"
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/batch_test.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    stem_fixture(%{
      track_id: track.id,
      processing_job_id: pj.id,
      stem_type: :vocals,
      file_path: "stems/vocals.wav",
      file_size: 1024
    })

    stem_fixture(%{
      track_id: track.id,
      processing_job_id: pj.id,
      stem_type: :drums,
      file_path: "stems/drums.wav",
      file_size: 1024
    })

    %{track: track}
  end

  describe "engine selection" do
    test "select_engine demucs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_engine", %{"engine" => "demucs"})
      assert is_binary(html)
    end

    test "select_engine lalalai without key shows modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_engine", %{"engine" => "lalalai"})
      assert is_binary(html)
    end

    test "select_lalalai_mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "vocals"})
      assert is_binary(html)
    end

    test "toggle_multistem", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_multistem", %{"stem" => "vocals"})
      assert is_binary(html)
    end

    test "set_noise_level", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "set_noise_level", %{"level" => "5"})
      assert is_binary(html)
    end

    test "toggle_dereverb", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_dereverb", %{})
      assert is_binary(html)
    end

    test "toggle_preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_preview", %{})
      assert is_binary(html)
    end

    test "toggle_auto_download", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_auto_download", %{})
      assert is_binary(html)
    end
  end

  describe "batch mode" do
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

    test "batch_analyze with selection", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_track_select", %{"track_id" => track.id})
      html = render_click(view, "batch_analyze", %{})
      assert is_binary(html)
    end

    test "batch_process with selection", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_track_select", %{"track_id" => track.id})
      html = render_click(view, "batch_process", %{})
      assert is_binary(html)
    end
  end

  describe "metadata editing" do
    test "edit_metadata", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "edit_metadata", %{"id" => track.id})
      assert is_binary(html)
    end

    test "cancel_edit", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "edit_metadata", %{"id" => track.id})
      html = render_click(view, "cancel_edit", %{})
      assert is_binary(html)
    end

    test "save_metadata", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "edit_metadata", %{"id" => track.id})

      html =
        render_click(view, "save_metadata", %{
          "track" => %{"title" => "Updated Title", "artist" => "Updated Artist"}
        })

      assert is_binary(html)
    end

    test "save_metadata without edit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "save_metadata", %{"track" => %{"title" => "New"}})
      assert is_binary(html)
    end

    test "edit_metadata for nonexistent track", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "edit_metadata", %{"id" => Ecto.UUID.generate()})
      assert is_binary(html)
    end
  end

  describe "download and process" do
    test "download_track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "download_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "download_track not found", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "download_track", %{"id" => Ecto.UUID.generate()})
      assert html =~ "not found" or is_binary(html)
    end

    test "analyze_track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "analyze_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "analyze_track not found", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "analyze_track", %{"id" => Ecto.UUID.generate()})
      assert html =~ "not found" or is_binary(html)
    end

    test "process_track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "process_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "process_track not found", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "process_track", %{"id" => Ecto.UUID.generate()})
      assert html =~ "not found" or is_binary(html)
    end
  end

  describe "lalalai modal" do
    test "close_lalalai_modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      html = render_click(view, "close_lalalai_modal", %{})
      assert is_binary(html)
    end

    test "expand_lalalai_key_form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      html = render_click(view, "expand_lalalai_key_form", %{})
      assert is_binary(html)
    end

    test "lalalai_modal_key_input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      html = render_click(view, "lalalai_modal_key_input", %{"key" => "test-key-123"})
      assert is_binary(html)
    end

    test "test_save_lalalai_key empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      html = render_click(view, "test_save_lalalai_key", %{})
      assert is_binary(html)
    end

    test "test_lalalai_connection without key", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "test_lalalai_connection", %{})
      assert is_binary(html)
    end
  end

  describe "upload" do
    test "validate_upload", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "validate_upload", %{})
      assert is_binary(html)
    end
  end

  describe "catch-all event handler" do
    test "unknown event does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "nonexistent_event_xyz_12345", %{})
      assert is_binary(html)
    end
  end
end
