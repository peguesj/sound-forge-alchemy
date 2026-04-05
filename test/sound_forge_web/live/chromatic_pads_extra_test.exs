defmodule SoundForgeWeb.ChromaticPadsExtraTest do
  @moduledoc """
  Tests for ChromaticPadsComponent untested events:
  assign_stem, clear_pad_stem, cancel_preset_entry, start_import_preset.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Pads Extra Track",
      artist: "Pads Artist",
      duration: 200
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/pads_extra.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/vocals.wav", file_size: 1024})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :drums, file_path: "stems/drums.wav", file_size: 1024})

    %{track: track}
  end

  describe "assign_stem" do
    test "assign_stem with kebab params", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      render_click(view, "load_in_pads", %{"track-id" => track.id})
      html = render_click(view, "assign_stem", %{"pad-id" => "0", "stem-id" => "0"})
      assert is_binary(html)
    end
  end

  describe "clear_pad_stem" do
    test "clear_pad_stem", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      render_click(view, "load_in_pads", %{"track-id" => track.id})
      html = render_click(view, "clear_pad_stem", %{"pad-id" => "0"})
      assert is_binary(html)
    end
  end

  describe "preset import" do
    test "start_import_preset", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = render_click(view, "start_import_preset", %{})
      assert is_binary(html)
    end

    test "cancel_preset_entry", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = render_click(view, "cancel_preset_entry", %{})
      assert is_binary(html)
    end
  end
end
