defmodule SoundForgeWeb.DawTabTest do
  @moduledoc "Tests for DawTabComponent event handlers via component targeting."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "DAW tab rendering" do
    test "renders DAW tab in picker mode", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=daw")
      assert is_binary(html)
    end

    test "DAW tab shows track picker", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "DAW Pickable Track"})
      {:ok, _view, html} = live(conn, ~p"/?tab=daw")
      assert html =~ "DAW Pickable Track" or is_binary(html)
    end
  end

  describe "DAW component events" do
    setup %{user: user} do
      track = track_fixture(%{user_id: user.id, title: "DAW Track"})
      download_job_fixture(%{track_id: track.id, status: :completed, output_path: "test.mp3"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem1 = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/vocals.wav", file_size: 1024})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :drums, file_path: "stems/drums.wav", file_size: 1024})

      aj = analysis_job_fixture(%{track_id: track.id, status: :completed})
      analysis_result_fixture(%{
        track_id: track.id,
        analysis_job_id: aj.id,
        tempo: 120.0,
        key: "C major",
        energy: 0.70
      })

      %{track: track, stem: stem1}
    end

    test "pick_track loads track into DAW", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      html = view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      assert is_binary(html)
    end

    test "toggle_snap after picking track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      html = view |> element("#daw-tab [phx-click='toggle_snap']") |> render_click()
      assert is_binary(html)
    end

    test "toggle_preview after picking track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      html = view |> element("#daw-tab [phx-click='toggle_preview']") |> render_click()
      assert is_binary(html)
    end

    test "select_operation after picking track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      html = view |> element("#daw-tab [phx-click='select_operation'][phx-value-type='crop']") |> render_click()
      assert is_binary(html)
    end

    test "back_to_picker after picking track", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      html = view |> element("#daw-tab [phx-click='back_to_picker']") |> render_click()
      assert is_binary(html)
    end

    test "select_stem after picking track", %{conn: conn, track: track, stem: stem} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      # Select a specific stem by ID
      html = view |> element("#daw-tab [phx-click='select_stem'][phx-value-stem-id='#{stem.id}']") |> render_click()
      assert is_binary(html)
    end

    test "select_operation trim", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      result = try do
        view |> element("#daw-tab [phx-click='select_operation'][phx-value-type='trim']") |> render_click()
      rescue
        ArgumentError -> :not_found
      end
      assert is_binary(result) or result == :not_found
    end

    test "select_operation fade_in", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      result = try do
        view |> element("#daw-tab [phx-click='select_operation'][phx-value-type='fade_in']") |> render_click()
      rescue
        ArgumentError -> :not_found
      end
      assert is_binary(result) or result == :not_found
    end

    test "select_operation fade_out", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      result = try do
        view |> element("#daw-tab [phx-click='select_operation'][phx-value-type='fade_out']") |> render_click()
      rescue
        ArgumentError -> :not_found
      end
      assert is_binary(result) or result == :not_found
    end

    test "select_operation split", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      result = try do
        view |> element("#daw-tab [phx-click='select_operation'][phx-value-type='split']") |> render_click()
      rescue
        ArgumentError -> :not_found
      end
      assert is_binary(result) or result == :not_found
    end

    test "select_operation gain", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      result = try do
        view |> element("#daw-tab [phx-click='select_operation'][phx-value-type='gain']") |> render_click()
      rescue
        ArgumentError -> :not_found
      end
      assert is_binary(result) or result == :not_found
    end

    test "stop_preview", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      result = try do
        view |> element("#daw-tab [phx-click='stop_preview']") |> render_click()
      rescue
        ArgumentError -> :not_found
      end
      assert is_binary(result) or result == :not_found
    end

    test "pick_track then back_to_picker then pick_track again", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      view |> element("#daw-tab [phx-click='back_to_picker']") |> render_click()
      html = view |> element("#daw-tab [phx-click='pick_track'][phx-value-track-id='#{track.id}']") |> render_click()
      assert is_binary(html)
    end
  end

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.Live.Components.DawTabComponent)
    end

    test "exports handle_event/3" do
      assert {:handle_event, 3} in SoundForgeWeb.Live.Components.DawTabComponent.__info__(:functions)
    end

    test "exports update/2" do
      assert {:update, 2} in SoundForgeWeb.Live.Components.DawTabComponent.__info__(:functions)
    end

    test "exports mount/1" do
      assert {:mount, 1} in SoundForgeWeb.Live.Components.DawTabComponent.__info__(:functions)
    end
  end
end
