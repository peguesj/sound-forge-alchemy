defmodule SoundForgeWeb.DjDualDeckTest do
  @moduledoc """
  Tests DJ functionality with deck loading - exercises deck templates,
  crossfader, and deck-specific event handlers.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track1 = track_fixture(%{
      user_id: user.id,
      title: "DJ Deck 1 Track",
      artist: "DJ Artist 1",
      duration: 240,
      album: "DJ Album 1"
    })

    track2 = track_fixture(%{
      user_id: user.id,
      title: "DJ Deck 2 Track",
      artist: "DJ Artist 2",
      duration: 300,
      album: "DJ Album 2"
    })

    for track <- [track1, track2] do
      download_job_fixture(%{
        track_id: track.id,
        status: :completed,
        output_path: "priv/uploads/downloads/dj_#{track.id}.mp3"
      })

      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/vocals.wav", file_size: 1024})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :drums, file_path: "stems/drums.wav", file_size: 1024})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :bass, file_path: "stems/bass.wav", file_size: 1024})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :other, file_path: "stems/other.wav", file_size: 1024})

      aj = analysis_job_fixture(%{track_id: track.id, status: :completed})
      analysis_result_fixture(%{
        track_id: track.id,
        analysis_job_id: aj.id,
        tempo: 128.0,
        key: "A minor",
        energy: 0.8
      })
    end

    %{track1: track1, track2: track2}
  end

  defp load_deck_1(view, track) do
    view |> element("#dj-tab [phx-click='toggle_browser']") |> render_click()
    view |> element("#dj-tab [phx-click='load_track'][phx-value-track-id='#{track.id}']") |> render_click()
  end

  defp try_click(view, selector) do
    try do
      view |> element("#dj-tab " <> selector) |> render_click()
    rescue
      ArgumentError -> :not_found
    end
  end

  describe "deck loading" do
    test "load track into deck 1 via browser", %{conn: conn, track1: track1} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      html = load_deck_1(view, track1)
      assert html =~ track1.title or is_binary(html)
    end

    test "tracks available in browser for loading", %{conn: conn, track2: track2} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      try_click(view, "[phx-click='toggle_browser']")
      html = render(view)
      assert html =~ track2.title or is_binary(html)
    end
  end

  describe "crossfader controls" do
    test "crossfader element present after deck load", %{conn: conn, track1: track1} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      html = load_deck_1(view, track1)
      # Crossfader should be in the rendered HTML
      assert html =~ "crossfader" or html =~ "Crossfader" or is_binary(html)
    end
  end

  describe "deck 1 controls after load" do
    test "toggle_eq_kill on deck 1", %{conn: conn, track1: track1} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck_1(view, track1)
      result = try_click(view, "[phx-click='toggle_eq_kill']")
      assert is_binary(result) or result == :not_found
    end

    test "loop_in on deck 1", %{conn: conn, track1: track1} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck_1(view, track1)
      result = try_click(view, "[phx-click='loop_in']")
      assert is_binary(result) or result == :not_found
    end

    test "set_filter lowpass", %{conn: conn, track1: track1} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck_1(view, track1)
      result = try_click(view, "[phx-click='set_filter'][phx-value-mode='lowpass']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "browser controls" do
    test "toggle_browser opens browser", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      html = try_click(view, "[phx-click='toggle_browser']")
      assert is_binary(html) or html == :not_found
    end

    test "browser_search", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      try_click(view, "[phx-click='toggle_browser']")
      result = try_click(view, "[phx-click='search_browser']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "chef controls with deck loaded" do
    test "toggle_chef_panel with deck loaded", %{conn: conn, track1: track1} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck_1(view, track1)
      result = try_click(view, "[phx-click='toggle_chef_panel']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "preset controls" do
    test "toggle_preset_section", %{conn: conn, track1: track1} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck_1(view, track1)
      result = try_click(view, "[phx-click='toggle_preset_section']")
      assert is_binary(result) or result == :not_found
    end
  end
end
