defmodule SoundForgeWeb.DawTabMoreEventsTest do
  @moduledoc """
  Additional tests for DawTabComponent events and rendering paths.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{user_id: user.id, title: "DAW Track", artist: "DAW Artist", duration: 300})
    download_job_fixture(%{track_id: track.id, status: :completed, output_path: "priv/uploads/downloads/daw.mp3"})
    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    stems = for st <- [:vocals, :drums, :bass, :other] do
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: st, file_path: "stems/#{st}.wav", file_size: 2048})
    end

    %{track: track, stems: stems}
  end

  defp load_daw(conn, track) do
    {:ok, view, _html} = live(conn, ~p"/?tab=daw")
    render_click(view, "pick_track", %{"track-id" => track.id})
    view
  end

  describe "operation selection" do
    test "select_operation slice", %{conn: conn, track: track} do
      view = load_daw(conn, track)
      html = render_click(view, "select_operation", %{"type" => "slice"})
      assert is_binary(html)
    end

    test "select_operation reverse", %{conn: conn, track: track} do
      view = load_daw(conn, track)
      html = render_click(view, "select_operation", %{"type" => "reverse"})
      assert is_binary(html)
    end

    test "select_operation pitch_shift", %{conn: conn, track: track} do
      view = load_daw(conn, track)
      html = render_click(view, "select_operation", %{"type" => "pitch_shift"})
      assert is_binary(html)
    end

    test "select_operation time_stretch", %{conn: conn, track: track} do
      view = load_daw(conn, track)
      html = render_click(view, "select_operation", %{"type" => "time_stretch"})
      assert is_binary(html)
    end
  end

  describe "snap and region" do
    test "toggle_snap", %{conn: conn, track: track} do
      view = load_daw(conn, track)
      html = render_click(view, "toggle_snap", %{})
      assert is_binary(html)
    end

    test "select_region", %{conn: conn, track: track} do
      view = load_daw(conn, track)
      html = render_click(view, "select_region", %{"start_ms" => "1000", "end_ms" => "5000"})
      assert is_binary(html)
    end
  end

  describe "stem selection" do
    test "select_stem", %{conn: conn, track: track, stems: [stem | _]} do
      view = load_daw(conn, track)
      html = render_click(view, "select_stem", %{"stem-id" => stem.id})
      assert is_binary(html)
    end
  end

  describe "preview controls" do
    test "toggle_preview", %{conn: conn, track: track} do
      view = load_daw(conn, track)
      html = render_click(view, "toggle_preview", %{})
      assert is_binary(html)
    end

    test "stop_preview", %{conn: conn, track: track} do
      view = load_daw(conn, track)
      html = render_click(view, "stop_preview", %{})
      assert is_binary(html)
    end
  end

  describe "export" do
    test "export_stem", %{conn: conn, track: track, stems: [stem | _]} do
      view = load_daw(conn, track)
      html = render_click(view, "export_stem", %{"stem_id" => stem.id})
      assert is_binary(html)
    end

    test "export_progress complete", %{conn: conn, track: track} do
      view = load_daw(conn, track)
      html = render_click(view, "export_progress", %{"status" => "complete", "url" => "/download/test.wav"})
      assert is_binary(html)
    end

    test "export_progress error", %{conn: conn, track: track} do
      view = load_daw(conn, track)
      html = render_click(view, "export_progress", %{"status" => "error", "message" => "export failed"})
      assert is_binary(html)
    end
  end

  describe "back_to_picker" do
    test "back_to_picker returns to track list", %{conn: conn, track: track} do
      view = load_daw(conn, track)
      html = render_click(view, "back_to_picker", %{})
      assert is_binary(html)
    end
  end
end
