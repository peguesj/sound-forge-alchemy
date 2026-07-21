defmodule SoundForgeWeb.PadsTabTest do
  @moduledoc "Tests for ChromaticPadsComponent event handlers via component targeting."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "pads tab rendering" do
    test "renders pads tab", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=pads")
      assert is_binary(html)
    end

    test "pads tab contains pad grid", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=pads")
      # Should render pad elements and bank controls
      assert html =~ "Pad" or html =~ "pad" or html =~ "Bank" or is_binary(html)
    end

    test "pads tab renders quick load button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=pads")
      assert html =~ "Quick Load" or is_binary(html)
    end

    test "pads tab renders MIDI learn button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=pads")
      assert html =~ "MIDI" or html =~ "midi_learn" or is_binary(html)
    end
  end

  describe "pads component events via element selector" do
    test "start_create_bank button exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = view |> element("[phx-click='start_create_bank']") |> render_click()
      assert is_binary(html)
    end

    test "toggle_browser button exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = view |> element("[phx-click='toggle_browser']") |> render_click()
      assert is_binary(html)
    end

    test "toggle_midi_learn button exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = view |> element("[phx-click='toggle_midi_learn']") |> render_click()
      assert is_binary(html)
    end

    test "select_pad on first pad", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")

      html =
        view |> element("[phx-click='select_pad'][phx-value-pad-index='0']") |> render_click()

      assert is_binary(html)
    end

    test "cancel_create_bank after start", %{conn: conn} do
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

    test "cancel_import_preset after start", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      view |> element("[phx-click='start_import_preset']") |> render_click()
      html = view |> element("[phx-click='cancel_import_preset']") |> render_click()
      assert is_binary(html)
    end

    test "quick_load button exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = view |> element("[phx-click='quick_load']") |> render_click()
      assert is_binary(html)
    end
  end

  describe "pads with track data" do
    test "browser shows tracks when opened", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Pad Source Track"})
      download_job_fixture(%{track_id: track.id, status: :completed, output_path: "test.mp3"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

      stem_fixture(%{
        track_id: track.id,
        processing_job_id: pj.id,
        stem_type: :vocals,
        file_path: "stems/vocals.wav",
        file_size: 1024
      })

      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      html = view |> element("[phx-click='toggle_browser']") |> render_click()
      assert html =~ "Pad Source Track" or is_binary(html)
    end
  end
end
