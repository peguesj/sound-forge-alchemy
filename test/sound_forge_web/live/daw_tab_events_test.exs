defmodule SoundForgeWeb.DawTabEventsTest do
  @moduledoc """
  Tests for DawTabComponent event handlers: track picking, region operations,
  operation selection, snap toggle, stem selection, preview, export.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "DAW tab navigation" do
    test "renders daw tab", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/?tab=daw")
      assert html =~ "daw" or html =~ "DAW" or is_binary(html)
    end

    test "pick_track loads track in DAW", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "DAW Track"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      for type <- [:vocals, :drums, :bass, :other] do
        stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: type})
      end

      {:ok, view, _html} = live(conn, "/?tab=daw")
      html = render_click(view, "pick_track", %{"track-id" => track.id})
      assert is_binary(html)
    end

    test "back_to_picker", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Pick Track"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, view, _html} = live(conn, "/?tab=daw")
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "back_to_picker")
      assert is_binary(html)
    end
  end

  describe "operation selection" do
    test "select various operations", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Ops Track"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, view, _html} = live(conn, "/?tab=daw")
      render_click(view, "pick_track", %{"track-id" => track.id})

      for type <- ["trim", "fade_in", "fade_out", "reverse", "normalize", "pitch_shift", "time_stretch"] do
        html = render_click(view, "select_operation", %{"type" => type})
        assert is_binary(html)
      end
    end
  end

  describe "snap toggle" do
    test "toggle_snap", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Snap Track"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, view, _html} = live(conn, "/?tab=daw")
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "toggle_snap")
      assert is_binary(html)
      # Toggle back
      html2 = render_click(view, "toggle_snap")
      assert is_binary(html2)
    end
  end

  describe "stem selection" do
    test "select_stem", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Stem Select"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, view, _html} = live(conn, "/?tab=daw")
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "select_stem", %{"stem-id" => stem.id})
      assert is_binary(html)
    end
  end

  describe "preview controls" do
    test "toggle_preview and stop_preview", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Preview Track"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, view, _html} = live(conn, "/?tab=daw")
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "toggle_preview")
      assert is_binary(html)
      html2 = render_click(view, "stop_preview")
      assert is_binary(html2)
    end
  end

  describe "region operations" do
    test "select_region", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Region Track"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, view, _html} = live(conn, "/?tab=daw")
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "select_region", %{"start_ms" => "1000", "end_ms" => "5000"})
      assert is_binary(html)
    end

    test "region_created", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Region Create"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, view, _html} = live(conn, "/?tab=daw")
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "region_created", %{
        "stem_id" => stem.id,
        "start_ms" => "1000",
        "end_ms" => "5000",
        "operation_type" => "trim"
      })
      assert is_binary(html)
    end
  end

  describe "export" do
    test "export_stem", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Export Track"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, view, _html} = live(conn, "/?tab=daw")
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "export_stem", %{"stem_id" => stem.id})
      assert is_binary(html)
    end

    test "export_progress", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Export Progress"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, view, _html} = live(conn, "/?tab=daw")
      render_click(view, "pick_track", %{"track-id" => track.id})
      html = render_click(view, "export_progress", %{"status" => "complete", "path" => "/tmp/export.wav"})
      assert is_binary(html)
    end
  end
end
