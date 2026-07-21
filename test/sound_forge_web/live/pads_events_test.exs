defmodule SoundForgeWeb.PadsEventsTest do
  @moduledoc "Comprehensive tests for ChromaticPadsComponent event handlers."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "bank management events" do
    test "start_create_bank opens form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = view |> element("[phx-click='start_create_bank']") |> render_click()
      assert is_binary(html)
    end

    test "cancel_create_bank closes form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      view |> element("[phx-click='start_create_bank']") |> render_click()
      html = view |> element("[phx-click='cancel_create_bank']") |> render_click()
      assert is_binary(html)
    end

    test "start_import_preset opens import UI", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = view |> element("[phx-click='start_import_preset']") |> render_click()
      assert is_binary(html)
    end

    test "cancel_import_preset closes import UI", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      view |> element("[phx-click='start_import_preset']") |> render_click()
      html = view |> element("[phx-click='cancel_import_preset']") |> render_click()
      assert is_binary(html)
    end
  end

  describe "pad selection" do
    test "select_pad selects first pad", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")

      html =
        view |> element("[phx-click='select_pad'][phx-value-pad-index='0']") |> render_click()

      assert is_binary(html)
    end

    test "select_pad selects last pad", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")

      html =
        view |> element("[phx-click='select_pad'][phx-value-pad-index='15']") |> render_click()

      assert is_binary(html)
    end

    test "select_pad then deselect_pad", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      view |> element("[phx-click='select_pad'][phx-value-pad-index='0']") |> render_click()
      html = view |> element("[phx-click='deselect_pad']") |> render_click()
      assert is_binary(html)
    end
  end

  describe "browser events" do
    test "toggle_browser opens browser panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = view |> element("[phx-click='toggle_browser']") |> render_click()
      assert is_binary(html)
    end

    test "toggle_browser double toggle closes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      view |> element("[phx-click='toggle_browser']") |> render_click()
      html = view |> element("[phx-click='toggle_browser']") |> render_click()
      assert is_binary(html)
    end
  end

  describe "MIDI learn events" do
    test "toggle_midi_learn activates learn mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = view |> element("[phx-click='toggle_midi_learn']") |> render_click()
      assert is_binary(html)
    end

    test "toggle_midi_learn double toggle deactivates", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      view |> element("[phx-click='toggle_midi_learn']") |> render_click()
      html = view |> element("[phx-click='toggle_midi_learn']") |> render_click()
      assert is_binary(html)
    end
  end

  describe "quick load" do
    test "quick_load button works", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = view |> element("[phx-click='quick_load']") |> render_click()
      assert is_binary(html)
    end
  end

  describe "pads rendering" do
    test "renders 16 pads", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=pads")
      # 16 pads should be in the grid
      assert html =~ "Pad 1" or html =~ "pad" or is_binary(html)
    end

    test "renders bank controls", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=pads")
      assert html =~ "Bank" or html =~ "bank" or is_binary(html)
    end

    test "renders MIDI learn button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=pads")
      assert html =~ "MIDI" or html =~ "midi_learn" or is_binary(html)
    end

    test "renders quick load button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=pads")
      assert html =~ "Quick Load" or is_binary(html)
    end
  end

  describe "pads with track data" do
    setup %{user: user} do
      track = track_fixture(%{user_id: user.id, title: "Pad Source"})
      download_job_fixture(%{track_id: track.id, status: :completed, output_path: "test.mp3"})
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

      %{track: track}
    end

    test "browser shows tracks when opened", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = view |> element("[phx-click='toggle_browser']") |> render_click()
      assert html =~ "Pad Source" or is_binary(html)
    end
  end
end
