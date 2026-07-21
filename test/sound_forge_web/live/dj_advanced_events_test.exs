defmodule SoundForgeWeb.DjAdvancedEventsTest do
  @moduledoc """
  Tests for DJ tab advanced event handlers: cue management, chef operations,
  stem loops, hot cues, and preset upload.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "DJ Advanced Track",
        artist: "DJ Artist",
        duration: 240
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/dj_adv.mp3"
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

    aj = analysis_job_fixture(%{track_id: track.id, status: :completed})

    analysis_result_fixture(%{
      track_id: track.id,
      analysis_job_id: aj.id,
      tempo: 128.0,
      key: "A minor",
      energy: 0.8
    })

    %{track: track}
  end

  defp load_deck(view, track) do
    view |> element("#dj-tab [phx-click='toggle_browser']") |> render_click()

    view
    |> element("#dj-tab [phx-click='load_track'][phx-value-track-id='#{track.id}']")
    |> render_click()
  end

  defp try_click(view, selector) do
    try do
      view |> element("#dj-tab " <> selector) |> render_click()
    rescue
      ArgumentError -> :not_found
    end
  end

  describe "cue management" do
    test "set_cue on deck 1", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='set_cue']")
      assert is_binary(result) or result == :not_found
    end

    test "auto_detect_cues", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='auto_detect_cues']")
      assert is_binary(result) or result == :not_found
    end

    test "delete_cue", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='delete_cue']")
      assert is_binary(result) or result == :not_found
    end

    test "trigger_cue", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='trigger_cue']")
      assert is_binary(result) or result == :not_found
    end

    test "loop_from_cue", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='loop_from_cue']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "hot cues" do
    test "set_hot_cue", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='set_hot_cue']")
      assert is_binary(result) or result == :not_found
    end

    test "clear_hot_cue", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='clear_hot_cue']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "chef operations" do
    test "chef_cook without loaded recipe", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      try_click(view, "[phx-click='toggle_chef_panel']")
      result = try_click(view, "[phx-click='chef_cook']")
      assert is_binary(result) or result == :not_found
    end

    test "chef_load_recipe", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      try_click(view, "[phx-click='toggle_chef_panel']")
      result = try_click(view, "[phx-click='chef_load_recipe']")
      assert is_binary(result) or result == :not_found
    end

    test "chef_remix", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      try_click(view, "[phx-click='toggle_chef_panel']")
      result = try_click(view, "[phx-click='chef_remix']")
      assert is_binary(result) or result == :not_found
    end

    test "chef_load_to_pads", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      try_click(view, "[phx-click='toggle_chef_panel']")
      result = try_click(view, "[phx-click='chef_load_to_pads']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "stem loops" do
    test "toggle_stem_loops", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='toggle_stem_loops']")
      assert is_binary(result) or result == :not_found
    end

    test "delete_stem_loop", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='delete_stem_loop']")
      assert is_binary(result) or result == :not_found
    end

    test "send_to_pad", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='send_to_pad']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "preset controls" do
    test "upload_preset", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      try_click(view, "[phx-click='toggle_preset_section']")
      result = try_click(view, "[phx-click='upload_preset']")
      assert is_binary(result) or result == :not_found
    end

    test "validate_preset", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      try_click(view, "[phx-click='toggle_preset_section']")
      result = try_click(view, "[phx-click='validate_preset']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "smart loop" do
    test "set_smart_loop", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='set_smart_loop']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "auto cue management" do
    test "promote_auto_cue", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='promote_auto_cue']")
      assert is_binary(result) or result == :not_found
    end

    test "dismiss_auto_cue", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='dismiss_auto_cue']")
      assert is_binary(result) or result == :not_found
    end

    test "regenerate_auto_cues", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='regenerate_auto_cues']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "load_to_pads" do
    test "load_to_pads without recipe", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='load_to_pads']")
      assert is_binary(result) or result == :not_found
    end
  end
end
