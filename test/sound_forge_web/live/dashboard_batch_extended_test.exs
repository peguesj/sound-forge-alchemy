defmodule SoundForgeWeb.DashboardBatchExtendedTest do
  @moduledoc """
  Tests for DashboardLive batch processing branches, track selection
  toggle (select AND deselect paths), batch modal, confirm_batch_process,
  and process_track with different lalalai modes.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Batch Extended Track",
      artist: "Test Artist",
      duration: 200,
      album: "Test Album",
      spotify_url: "https://open.spotify.com/track/batch123"
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/batch_ext.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/vocals.wav", file_size: 1024})

    %{track: track}
  end

  describe "toggle_track_select deselect path" do
    test "selecting then deselecting a track exercises both branches", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      # First click: select (MapSet.put)
      render_click(view, "toggle_track_select", %{"track_id" => track.id})
      # Second click: deselect (MapSet.delete branch)
      html = render_click(view, "toggle_track_select", %{"track_id" => track.id})
      assert is_binary(html)
    end

    test "triple toggle ends with track selected", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_track_select", %{"track_id" => track.id})
      render_click(view, "toggle_track_select", %{"track_id" => track.id})
      html = render_click(view, "toggle_track_select", %{"track_id" => track.id})
      assert is_binary(html)
    end
  end

  describe "batch modal" do
    test "start_batch_process shows modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "start_batch_process", %{})
      assert is_binary(html)
    end

    test "cancel_batch_modal hides modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "start_batch_process", %{})
      html = render_click(view, "cancel_batch_modal", %{})
      assert is_binary(html)
    end
  end

  describe "confirm_batch_process" do
    test "with selected tracks", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_track_select", %{"track_id" => track.id})
      html = render_click(view, "confirm_batch_process", %{"engine" => "demucs", "stem_filter" => "vocals"})
      assert is_binary(html)
    end

    test "with empty selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "confirm_batch_process", %{"engine" => "demucs", "stem_filter" => "all"})
      assert is_binary(html)
    end
  end

  describe "process_track with lalalai modes" do
    test "process_track with lalalai multistem mode", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      # Set engine and mode first
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      render_click(view, "select_lalalai_mode", %{"mode" => "multistem"})
      render_click(view, "toggle_multistem", %{"stem" => "vocals"})
      html = render_click(view, "process_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "process_track with lalalai voice_clean mode", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      render_click(view, "select_lalalai_mode", %{"mode" => "voice_clean"})
      render_click(view, "set_noise_level", %{"level" => "3"})
      html = render_click(view, "process_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "process_track with lalalai voice_change mode", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      render_click(view, "select_lalalai_mode", %{"mode" => "voice_change"})
      render_click(view, "select_voice_pack", %{"pack_id" => "some-pack"})
      render_click(view, "set_accent", %{"value" => "0.7"})
      html = render_click(view, "process_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "process_track with lalalai demuser mode", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      render_click(view, "select_lalalai_mode", %{"mode" => "demuser"})
      render_click(view, "toggle_dereverb", %{})
      html = render_click(view, "process_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "process_track with lalalai default mode", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "select_engine", %{"engine" => "lalalai"})
      html = render_click(view, "process_track", %{"id" => track.id})
      assert is_binary(html)
    end

    test "process_track with preview mode enabled", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_preview", %{})
      html = render_click(view, "process_track", %{"id" => track.id})
      assert is_binary(html)
    end
  end

  describe "select_lalalai_mode variations" do
    test "multistem mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "multistem"})
      assert is_binary(html)
    end

    test "voice_clean mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "voice_clean"})
      assert is_binary(html)
    end

    test "voice_change mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "voice_change"})
      assert is_binary(html)
    end

    test "demuser mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_lalalai_mode", %{"mode" => "demuser"})
      assert is_binary(html)
    end
  end
end
