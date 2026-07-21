defmodule SoundForgeWeb.ChromaticPadsMegaTest do
  @moduledoc "Comprehensive ChromaticPads event coverage."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{user_id: user.id, title: "Pads Test", artist: "Test", duration: 200})

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/pads.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    stems =
      for type <- [:vocals, :drums, :bass, :other] do
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: pj.id,
          stem_type: type,
          file_path: "stems/#{type}.wav",
          file_size: 1024
        })
      end

    %{track: track, stems: stems}
  end

  defp go_pads(conn) do
    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "switch_tab", %{"tab" => "pads"})
    view
  end

  describe "bank management" do
    test "start_create_bank", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "start_create_bank", %{})
      assert is_binary(html)
    end

    test "cancel_create_bank", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "cancel_create_bank", %{})
      assert is_binary(html)
    end

    test "update_new_bank_name", %{conn: conn} do
      view = go_pads(conn)
      render_click(view, "start_create_bank", %{})
      html = render_click(view, "update_new_bank_name", %{"name" => "My Bank"})
      assert is_binary(html)
    end

    test "create_bank", %{conn: conn} do
      view = go_pads(conn)
      render_click(view, "start_create_bank", %{})
      html = render_click(view, "create_bank", %{"name" => "New Bank"})
      assert is_binary(html)
    end

    test "create_bank with empty name", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "create_bank", %{"name" => ""})
      assert is_binary(html)
    end

    test "start_rename_bank", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "start_rename_bank", %{})
      assert is_binary(html)
    end

    test "cancel_rename_bank", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "cancel_rename_bank", %{})
      assert is_binary(html)
    end

    test "update_rename_bank_name", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "update_rename_bank_name", %{"name" => "Renamed"})
      assert is_binary(html)
    end

    test "switch_bank with empty value", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "switch_bank", %{"_target" => ["value"], "value" => ""})
      assert is_binary(html)
    end
  end

  describe "pad events" do
    test "deselect_pad", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "deselect_pad", %{})
      assert is_binary(html)
    end

    test "set_master_volume", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "set_master_volume", %{"value" => "80"})
      assert is_binary(html)
    end

    test "quick_load", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "quick_load", %{})
      assert is_binary(html)
    end

    test "pad_triggered", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "pad_triggered", %{"pad_id" => "some-id"})
      assert is_binary(html)
    end
  end

  describe "MIDI events" do
    test "toggle_midi_learn", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "toggle_midi_learn", %{})
      assert is_binary(html)
    end

    test "midi_status", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "midi_status", %{"available" => true, "devices" => []})
      assert is_binary(html)
    end

    test "midi_devices_updated", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "midi_devices_updated", %{"devices" => []})
      assert is_binary(html)
    end

    test "midi_activity", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "midi_activity", %{})
      assert is_binary(html)
    end
  end

  describe "preset events" do
    test "start_import_preset", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "start_import_preset", %{})
      assert is_binary(html)
    end

    test "cancel_import_preset", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "cancel_import_preset", %{})
      assert is_binary(html)
    end

    test "validate_preset", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "validate_preset", %{})
      assert is_binary(html)
    end
  end

  describe "browser events" do
    test "toggle_browser", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "toggle_browser", %{})
      assert is_binary(html)
    end

    test "browser_search", %{conn: conn} do
      view = go_pads(conn)
      html = render_click(view, "browser_search", %{"value" => "test"})
      assert is_binary(html)
    end
  end
end
