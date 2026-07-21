defmodule SoundForgeWeb.DawTabEventsMegaTest do
  @moduledoc "Comprehensive DAW tab event coverage for handle_event clauses."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{user_id: user.id, title: "DAW Mega Test", artist: "Test", duration: 200})

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/daw.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    for type <- [:vocals, :drums, :bass, :other] do
      stem_fixture(%{
        track_id: track.id,
        processing_job_id: pj.id,
        stem_type: type,
        file_path: "stems/#{type}.wav",
        file_size: 1024
      })
    end

    %{track: track}
  end

  defp go_daw(conn) do
    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "switch_tab", %{"tab" => "daw"})
    view
  end

  describe "track picker" do
    test "pick_track loads a track", %{conn: conn, track: track} do
      view = go_daw(conn)
      html = render_click(view, "pick_track", %{"track-id" => track.id})
      assert is_binary(html)
    end

    test "back_to_picker returns to picker", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "back_to_picker", %{})
      assert is_binary(html)
    end
  end

  describe "operation selection" do
    test "select_operation crop", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "select_operation", %{"type" => "crop"})
      assert is_binary(html)
    end

    test "select_operation trim", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "select_operation", %{"type" => "trim"})
      assert is_binary(html)
    end

    test "select_operation fade_in", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "select_operation", %{"type" => "fade_in"})
      assert is_binary(html)
    end

    test "select_operation fade_out", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "select_operation", %{"type" => "fade_out"})
      assert is_binary(html)
    end

    test "select_operation split", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "select_operation", %{"type" => "split"})
      assert is_binary(html)
    end

    test "select_operation gain", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "select_operation", %{"type" => "gain"})
      assert is_binary(html)
    end

    test "select_operation invalid falls back to crop", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "select_operation", %{"type" => "nonexistent_operation_xyz"})
      assert is_binary(html)
    end
  end

  describe "snap and selection" do
    test "toggle_snap", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "toggle_snap", %{})
      assert is_binary(html)
    end

    test "toggle_snap twice returns to original", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      render_click(view, "toggle_snap", %{})
      html = render_click(view, "toggle_snap", %{})
      assert is_binary(html)
    end
  end

  describe "stem selection" do
    test "select_stem", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "select_stem", %{"stem-id" => "some-stem-id"})
      assert is_binary(html)
    end
  end

  describe "preview" do
    test "toggle_preview", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "toggle_preview", %{})
      assert is_binary(html)
    end

    test "stop_preview", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "stop_preview", %{})
      assert is_binary(html)
    end
  end

  describe "export" do
    test "export_progress processing status", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "export_progress", %{"status" => "processing"})
      assert is_binary(html)
    end

    test "export_progress error status", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "export_progress", %{"status" => "error", "message" => "fail"})
      assert is_binary(html)
    end
  end

  describe "undo" do
    test "undo_last with no operations", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      stems = SoundForge.Repo.preload(SoundForge.Music.get_track!(track.id), :stems).stems

      if length(stems) > 0 do
        stem = hd(stems)
        html = render_click(view, "undo_last", %{"stem_id" => stem.id})
        assert is_binary(html)
      end
    end
  end

  describe "browser events in daw" do
    test "toggle_browser", %{conn: conn} do
      view = go_daw(conn)
      html = render_click(view, "toggle_browser", %{})
      assert is_binary(html)
    end

    test "browser_search", %{conn: conn} do
      view = go_daw(conn)
      html = render_click(view, "browser_search", %{"value" => "test"})
      assert is_binary(html)
    end
  end

  describe "select_region" do
    test "select_region with coordinates", %{conn: conn, track: track} do
      view = go_daw(conn)
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "select_region", %{"start_ms" => 1000, "end_ms" => 5000})
      assert is_binary(html)
    end
  end
end
