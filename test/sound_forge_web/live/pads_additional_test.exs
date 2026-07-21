defmodule SoundForgeWeb.PadsAdditionalTest do
  @moduledoc """
  Additional tests for ChromaticPadsComponent events and rendering branches.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Pads Track",
        artist: "Pads Artist",
        duration: 200
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/pads.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    stems =
      for st <- [:vocals, :drums, :bass, :other] do
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: pj.id,
          stem_type: st,
          file_path: "stems/#{st}.wav",
          file_size: 1024
        })
      end

    %{track: track, stems: stems}
  end

  defp setup_pads(conn, track) do
    {:ok, view, _html} = live(conn, ~p"/?tab=pads")
    render_click(view, "load_in_pads", %{"track-id" => track.id})
    view
  end

  describe "pad property updates" do
    test "update_pad_velocity", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      render_click(view, "select_pad", %{"pad-id" => "0"})
      html = render_click(view, "update_pad_velocity", %{"pad-id" => "0", "value" => "0.5"})
      assert is_binary(html)
    end

    test "update_pad_start_time", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      render_click(view, "select_pad", %{"pad-id" => "0"})
      html = render_click(view, "update_pad_start_time", %{"pad-id" => "0", "value" => "1.5"})
      assert is_binary(html)
    end

    test "update_pad_end_time", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      render_click(view, "select_pad", %{"pad-id" => "0"})
      html = render_click(view, "update_pad_end_time", %{"pad-id" => "0", "value" => "3.0"})
      assert is_binary(html)
    end
  end

  describe "bank operations" do
    test "delete_bank", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      html = render_click(view, "delete_bank", %{})
      assert is_binary(html)
    end

    test "switch_bank with empty value", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      html = render_click(view, "switch_bank", %{"_target" => ["bank"], "value" => ""})
      assert is_binary(html)
    end
  end

  describe "pad_triggered event" do
    test "pad_triggered does not crash", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      html = render_click(view, "pad_triggered", %{"pad_id" => "0"})
      assert is_binary(html)
    end
  end

  describe "clear operations" do
    test "clear_pad_full on pad", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      html = render_click(view, "clear_pad_full", %{"pad-id" => "0"})
      assert is_binary(html)
    end

    test "clear_pad_stem after selecting", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      render_click(view, "select_pad", %{"pad-id" => "0"})
      html = render_click(view, "clear_pad_stem", %{})
      assert is_binary(html)
    end
  end

  describe "MIDI learn operations" do
    test "midi_learn_param for volume", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      render_click(view, "toggle_midi_learn", %{})
      html = render_click(view, "midi_learn_param", %{"param" => "volume", "pad-index" => "0"})
      assert is_binary(html)
    end

    test "midi_status event", %{conn: conn, track: track} do
      view = setup_pads(conn, track)

      html =
        render_click(view, "midi_status", %{"available" => true, "devices" => ["Test Device"]})

      assert is_binary(html)
    end

    test "midi_devices_updated event", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      html = render_click(view, "midi_devices_updated", %{"devices" => ["Device A", "Device B"]})
      assert is_binary(html)
    end

    test "midi_activity event", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      html = render_click(view, "midi_activity", %{})
      assert is_binary(html)
    end
  end

  describe "browser on pads" do
    test "toggle_browser", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      html = render_click(view, "toggle_browser", %{})
      assert is_binary(html)
    end

    test "browser_search", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      render_click(view, "toggle_browser", %{})
      html = render_click(view, "browser_search", %{"value" => "search term"})
      assert is_binary(html)
    end

    test "browser_load_track", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      render_click(view, "toggle_browser", %{})
      html = render_click(view, "browser_load_track", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end

  describe "preset import on pads" do
    test "start_import_preset and cancel", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      render_click(view, "start_import_preset", %{})
      html = render_click(view, "cancel_import_preset", %{})
      assert is_binary(html)
    end

    test "validate_preset is no-op", %{conn: conn, track: track} do
      view = setup_pads(conn, track)
      html = render_click(view, "validate_preset", %{})
      assert is_binary(html)
    end
  end
end
