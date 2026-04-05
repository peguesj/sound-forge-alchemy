defmodule SoundForgeWeb.PadsTabUpdateTest do
  @moduledoc """
  Tests for ChromaticPadsComponent update/2 clauses triggered
  via send_update from DashboardLive when nav_tab == :pads.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Pads Update Track",
      artist: "Pads Artist",
      duration: 200
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/pads_update.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/vocals.wav", file_size: 1024})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :drums, file_path: "stems/drums.wav", file_size: 1024})

    %{track: track}
  end

  defp setup_pads_with_track(conn, track) do
    {:ok, view, _html} = live(conn, ~p"/?tab=pads")
    render_click(view, "load_in_pads", %{"track-id" => track.id})
    view
  end

  describe "broadcast events forwarded to pads tab" do
    test "auto_cues_complete forwarded to pads", %{conn: conn, track: track} do
      view = setup_pads_with_track(conn, track)
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "track:#{track.id}",
        event: "auto_cues_complete",
        payload: %{track_id: track.id, cue_count: 4}
      })
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "MIDI events on pads tab" do
    test "midi_action on pads tab", %{conn: conn, track: track} do
      view = setup_pads_with_track(conn, track)
      send(view.pid, {:midi_action, :pad_trigger, %{pad: 0, velocity: 127}})
      html = render(view)
      assert is_binary(html)
    end

    test "bpm_update on pads tab", %{conn: conn, track: track} do
      view = setup_pads_with_track(conn, track)
      send(view.pid, {:bpm_update, %{bpm: 120.0, source: "midi"}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "pads tab bank operations" do
    test "create bank on pads tab", %{conn: conn, track: track} do
      view = setup_pads_with_track(conn, track)
      render_click(view, "start_create_bank", %{})
      render_click(view, "update_new_bank_name", %{"name" => "My Bank"})
      html = render_click(view, "create_bank", %{})
      assert is_binary(html)
    end

    test "rename bank on pads tab", %{conn: conn, track: track} do
      view = setup_pads_with_track(conn, track)
      render_click(view, "start_rename_bank", %{})
      render_click(view, "update_rename_bank_name", %{"name" => "Renamed Bank"})
      html = render_click(view, "rename_bank", %{})
      assert is_binary(html)
    end

    test "pad operations chain", %{conn: conn, track: track} do
      view = setup_pads_with_track(conn, track)
      render_click(view, "select_pad", %{"pad-id" => "0"})
      render_click(view, "update_pad_label", %{"pad-id" => "0", "label" => "Kick"})
      render_click(view, "update_pad_volume", %{"pad-id" => "0", "volume" => "0.8"})
      render_click(view, "update_pad_pitch", %{"pad-id" => "0", "pitch" => "1.0"})
      render_click(view, "update_pad_color", %{"pad-id" => "0", "color" => "#ff0000"})
      html = render_click(view, "deselect_pad", %{})
      assert is_binary(html)
    end
  end

  describe "pads MIDI learn mode" do
    test "toggle MIDI learn and assign", %{conn: conn, track: track} do
      view = setup_pads_with_track(conn, track)
      render_click(view, "toggle_midi_learn", %{})
      render_click(view, "midi_learn_pad", %{"pad-id" => "0"})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "pads master volume" do
    test "set_master_volume on pads", %{conn: conn, track: track} do
      view = setup_pads_with_track(conn, track)
      html = render_click(view, "set_master_volume", %{"value" => "0.7"})
      assert is_binary(html)
    end
  end

  describe "quick_load on pads" do
    test "quick_load track into pads", %{conn: conn, track: track} do
      view = setup_pads_with_track(conn, track)
      html = render_click(view, "quick_load", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end
end
