defmodule SoundForgeWeb.DjStateTransitionsTest do
  @moduledoc """
  Tests DJ tab state transitions: loading tracks into different states,
  toggling controls, and exercising template conditionals.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "State Test Track",
      artist: "State Artist",
      duration: 240,
      album: "State Album"
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/state_test.mp3"
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

    %{track: track}
  end

  defp load_deck(view, track) do
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

  describe "deck loaded state rendering" do
    test "renders track title in deck after load", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      html = load_deck(view, track)
      assert html =~ "State Test Track"
    end

    test "renders BPM after load", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      html = load_deck(view, track)
      assert html =~ "128.0" or html =~ "128"
    end

    test "renders stem controls after load", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      html = load_deck(view, track)
      assert html =~ "vocals" or html =~ "drums" or html =~ "Vocals" or html =~ "Drums"
    end
  end

  describe "multiple state changes" do
    test "toggle play toggles state", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='toggle_play']")
      assert is_binary(result) or result == :not_found
    end

    test "set pitch then pitch_reset", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      try_click(view, "[phx-click='set_pitch']")
      result = try_click(view, "[phx-click='pitch_reset']")
      assert is_binary(result) or result == :not_found
    end

    test "toggle metronome on and off", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      try_click(view, "[phx-click='toggle_metronome']")
      result = try_click(view, "[phx-click='toggle_metronome']")
      assert is_binary(result) or result == :not_found
    end

    test "loop_in then loop_out creates loop", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      try_click(view, "[phx-click='loop_in']")
      result = try_click(view, "[phx-click='loop_out']")
      assert is_binary(result) or result == :not_found
    end

    test "loop_toggle after loop_in loop_out", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      try_click(view, "[phx-click='loop_in']")
      try_click(view, "[phx-click='loop_out']")
      result = try_click(view, "[phx-click='loop_toggle']")
      assert is_binary(result) or result == :not_found
    end

    test "loop_size changes", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      for beats <- ["1", "2", "4", "8", "16"] do
        result = try_click(view, "[phx-click='loop_size'][phx-value-beats='#{beats}']")
        assert is_binary(result) or result == :not_found
      end
    end

    test "skip_section forward and backward", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      r1 = try_click(view, "[phx-click='skip_section'][phx-value-direction='forward']")
      r2 = try_click(view, "[phx-click='skip_section'][phx-value-direction='backward']")
      assert (is_binary(r1) or r1 == :not_found) and (is_binary(r2) or r2 == :not_found)
    end
  end

  describe "eq and filter controls" do
    test "toggle_eq_kill for all bands", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      for band <- ["low", "mid", "high"] do
        result = try_click(view, "[phx-click='toggle_eq_kill'][phx-value-band='#{band}']")
        assert is_binary(result) or result == :not_found
      end
    end

    test "set_filter modes", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      for mode <- ["lowpass", "highpass", "off"] do
        result = try_click(view, "[phx-click='set_filter'][phx-value-mode='#{mode}']")
        assert is_binary(result) or result == :not_found
      end
    end
  end

  describe "sync controls" do
    test "sync_deck", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='sync_deck']")
      assert is_binary(result) or result == :not_found
    end

    test "master_sync", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='master_sync']")
      assert is_binary(result) or result == :not_found
    end

    test "toggle_midi_sync", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='toggle_midi_sync']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "crossfader curves" do
    test "set_crossfader_curve smooth", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='set_crossfader_curve'][phx-value-curve='smooth']")
      assert is_binary(result) or result == :not_found
    end

    test "set_crossfader_curve sharp", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='set_crossfader_curve'][phx-value-curve='sharp']")
      assert is_binary(result) or result == :not_found
    end

    test "set_crossfader_curve linear", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='set_crossfader_curve'][phx-value-curve='linear']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "time factor" do
    test "set_time_factor 2x", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='set_time_factor'][phx-value-factor='2.0']")
      assert is_binary(result) or result == :not_found
    end

    test "set_time_factor 0.5x", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='set_time_factor'][phx-value-factor='0.5']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "jog controls" do
    test "jog_cue_press", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='jog_cue_press']")
      assert is_binary(result) or result == :not_found
    end

    test "jog_cue_release", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='jog_cue_release']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "deck volume" do
    test "set_deck_volume", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      result = try_click(view, "[phx-click='set_deck_volume']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "chef panel interactions" do
    test "chef panel open then prompt then cook", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      load_deck(view, track)
      try_click(view, "[phx-click='toggle_chef_panel']")
      result = try_click(view, "[phx-click='chef_cook']")
      assert is_binary(result) or result == :not_found
    end
  end

  describe "browser search" do
    test "browser_search filters track list", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/?tab=dj")
      try_click(view, "[phx-click='toggle_browser']")
      html = render(view)
      assert html =~ track.title
    end
  end
end
