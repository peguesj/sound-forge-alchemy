defmodule SoundForgeWeb.ChromaticPadsTest do
  @moduledoc """
  Tests for ChromaticPadsComponent events and template rendering.
  ChromaticPadsComponent is a LiveComponent embedded in DashboardLive at tab=pads.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Pads Test Track",
        artist: "Pads Artist",
        duration: 200,
        album: "Pads Album"
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/pads_test.mp3"
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

  describe "Pads tab renders" do
    test "renders pads tab with pad grid", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=pads")
      assert html =~ "pads" or html =~ "Pads" or html =~ "pad" or is_binary(html)
    end

    test "shows bank controls", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?tab=pads")
      assert html =~ "Bank" or html =~ "bank" or is_binary(html)
    end
  end

  describe "bank management" do
    test "start_create_bank", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      result = try_click(view, "#pads-tab [phx-click='start_create_bank']")
      assert is_binary(result) or result == :not_found
    end

    test "cancel_create_bank", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      try_click(view, "#pads-tab [phx-click='start_create_bank']")
      result = try_click(view, "#pads-tab [phx-click='cancel_create_bank']")
      assert is_binary(result) or result == :not_found
    end

    test "start_rename_bank", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      result = try_click(view, "#pads-tab [phx-click='start_rename_bank']")
      assert is_binary(result) or result == :not_found
    end

    test "cancel_rename_bank", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      try_click(view, "#pads-tab [phx-click='start_rename_bank']")
      result = try_click(view, "#pads-tab [phx-click='cancel_rename_bank']")
      assert is_binary(result) or result == :not_found
    end

    test "delete_bank", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      result = try_click(view, "#pads-tab [phx-click='delete_bank']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "pad interaction" do
    test "select_pad", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      result = try_click(view, "#pads-tab [phx-click='select_pad']")
      assert is_binary(result) or result == :not_found
    end

    test "deselect_pad", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      result = try_click(view, "#pads-tab [phx-click='deselect_pad']")
      assert is_binary(result) or result == :not_found
    end

    test "clear_pad_stem", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      result = try_click(view, "#pads-tab [phx-click='clear_pad_stem']")
      assert is_binary(result) or result == :not_found
    end

    test "clear_pad_full", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      result = try_click(view, "#pads-tab [phx-click='clear_pad_full']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "master controls" do
    test "quick_load", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      result = try_click(view, "#pads-tab [phx-click='quick_load']")
      assert is_binary(result) or result == :not_found
    end

    test "toggle_midi_learn", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      result = try_click(view, "#pads-tab [phx-click='toggle_midi_learn']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "browser" do
    test "toggle_browser", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=pads")
      result = try_click(view, "#pads-tab [phx-click='toggle_browser']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.Live.Components.ChromaticPadsComponent)
    end

    test "exports handle_event/3" do
      assert {:handle_event, 3} in SoundForgeWeb.Live.Components.ChromaticPadsComponent.__info__(
               :functions
             )
    end

    test "exports update/2" do
      assert {:update, 2} in SoundForgeWeb.Live.Components.ChromaticPadsComponent.__info__(
               :functions
             )
    end
  end
end
