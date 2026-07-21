defmodule SoundForgeWeb.DawTabExtendedTest do
  @moduledoc """
  Tests for DawTabComponent event handlers not covered by existing tests:
  region operations, apply_operation, apply_split, split_marker_moved, undo_last.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "DAW Extended Track",
        artist: "DAW Artist",
        duration: 200
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/daw_ext.mp3"
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

    stem_fixture(%{
      track_id: track.id,
      processing_job_id: pj.id,
      stem_type: :bass,
      file_path: "stems/bass.wav",
      file_size: 1024
    })

    stem_fixture(%{
      track_id: track.id,
      processing_job_id: pj.id,
      stem_type: :other,
      file_path: "stems/other.wav",
      file_size: 1024
    })

    %{track: track}
  end

  defp try_click(view, selector) do
    try do
      view |> element(selector) |> render_click()
    rescue
      ArgumentError -> :not_found
    end
  end

  defp load_track_in_daw(view, track) do
    # Navigate to DAW tab and pick a track
    render_click(view, "pick_track", %{"track-id" => track.id})
  end

  describe "region operations" do
    test "region_created via render_click", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)

      html =
        render_click(view, "region_created", %{
          "stem_type" => "vocals",
          "start" => "1.0",
          "end" => "3.0",
          "id" => "region-1"
        })

      assert is_binary(html)
    end

    test "region_updated", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)

      html =
        render_click(view, "region_updated", %{
          "stem_type" => "vocals",
          "id" => "region-1",
          "start" => "1.5",
          "end" => "3.5"
        })

      assert is_binary(html)
    end

    test "region_removed", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)

      html =
        render_click(view, "region_removed", %{
          "stem_type" => "vocals",
          "id" => "region-1"
        })

      assert is_binary(html)
    end

    test "select_region", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)

      html =
        render_click(view, "select_region", %{
          "stem_type" => "vocals",
          "id" => "region-1"
        })

      assert is_binary(html)
    end
  end

  describe "operations" do
    test "select_operation", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)
      html = render_click(view, "select_operation", %{"op" => "gain"})
      assert is_binary(html)
    end

    test "apply_operation gain", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)

      html =
        render_click(view, "apply_operation", %{
          "stem_type" => "vocals",
          "operation" => "gain",
          "params" => %{"amount" => "0.5"}
        })

      assert is_binary(html)
    end

    test "apply_operation reverse", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)

      html =
        render_click(view, "apply_operation", %{
          "stem_type" => "drums",
          "operation" => "reverse",
          "params" => %{}
        })

      assert is_binary(html)
    end

    test "apply_split", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)

      html =
        render_click(view, "apply_split", %{
          "stem_type" => "vocals",
          "position" => "5.0"
        })

      assert is_binary(html)
    end

    test "split_marker_moved", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)

      html =
        render_click(view, "split_marker_moved", %{
          "stem_type" => "vocals",
          "id" => "split-1",
          "position" => "6.0"
        })

      assert is_binary(html)
    end
  end

  describe "undo" do
    test "undo_last", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)
      html = render_click(view, "undo_last", %{"stem_type" => "vocals"})
      assert is_binary(html)
    end
  end

  describe "snap and preview" do
    test "toggle_snap", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)
      html = render_click(view, "toggle_snap", %{})
      assert is_binary(html)
    end

    test "toggle_preview", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)
      html = render_click(view, "toggle_preview", %{})
      assert is_binary(html)
    end

    test "stop_preview", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)
      html = render_click(view, "stop_preview", %{})
      assert is_binary(html)
    end
  end

  describe "export" do
    test "export_stem", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)
      html = render_click(view, "export_stem", %{"stem_type" => "vocals"})
      assert is_binary(html)
    end
  end

  describe "stem selection" do
    test "select_stem", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=daw")
      load_track_in_daw(view, track)
      html = render_click(view, "select_stem", %{"stem_type" => "drums"})
      assert is_binary(html)
    end
  end
end
