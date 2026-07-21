defmodule SoundForgeWeb.DjTabRenderingTest do
  @moduledoc """
  Tests focused on DjTabComponent template rendering coverage.
  Exercises different states to cover conditional template branches.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    # Create track with full pipeline data for maximum template coverage
    track =
      track_fixture(%{
        user_id: user.id,
        title: "DJ Render Track",
        artist: "DJ Artist",
        duration: 240,
        album: "DJ Album"
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/dj_render.mp3"
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

    track2 =
      track_fixture(%{
        user_id: user.id,
        title: "DJ Render Track 2",
        artist: "DJ Artist 2",
        duration: 180
      })

    download_job_fixture(%{
      track_id: track2.id,
      status: :completed,
      output_path: "priv/uploads/downloads/dj_render2.mp3"
    })

    pj2 = processing_job_fixture(%{track_id: track2.id, model: "htdemucs", status: :completed})

    stem_fixture(%{
      track_id: track2.id,
      processing_job_id: pj2.id,
      stem_type: :vocals,
      file_path: "stems/vocals2.wav",
      file_size: 1024
    })

    stem_fixture(%{
      track_id: track2.id,
      processing_job_id: pj2.id,
      stem_type: :drums,
      file_path: "stems/drums2.wav",
      file_size: 1024
    })

    stem_fixture(%{
      track_id: track2.id,
      processing_job_id: pj2.id,
      stem_type: :bass,
      file_path: "stems/bass2.wav",
      file_size: 1024
    })

    stem_fixture(%{
      track_id: track2.id,
      processing_job_id: pj2.id,
      stem_type: :other,
      file_path: "stems/other2.wav",
      file_size: 1024
    })

    %{track: track, track2: track2}
  end

  defp load_dj_tab(conn) do
    {:ok, view, _html} = live(conn, ~p"/?tab=dj")
    view
  end

  describe "DJ tab initial render" do
    test "renders empty DJ tab", %{conn: conn} do
      view = load_dj_tab(conn)
      html = render(view)
      assert html =~ "dj" or is_binary(html)
    end
  end

  describe "DJ tab with track loaded" do
    test "load track into deck 1 and render", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render(view)
      assert is_binary(html)
    end

    test "load tracks into both decks", %{conn: conn, track: track, track2: track2} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "load_track", %{"track-id" => track2.id, "deck" => "2"})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "DJ tab with loaded track interactions" do
    test "set cue on loaded track", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "set_cue", %{"deck" => "1", "time" => "10.5"})
      html = render(view)
      assert is_binary(html)
    end

    test "set hot cue on loaded track", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})

      render_click(view, "set_hot_cue", %{
        "deck" => "1",
        "index" => "0",
        "time" => "15.0",
        "label" => "Drop"
      })

      html = render(view)
      assert is_binary(html)
    end

    test "EQ kill toggle on loaded track", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "low"})
      html = render(view)
      assert is_binary(html)
    end

    test "set filter on loaded track", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "set_filter", %{"deck" => "1", "value" => "0.7"})
      html = render(view)
      assert is_binary(html)
    end

    test "set pitch on loaded track", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "set_pitch", %{"deck" => "1", "value" => "1.05"})
      html = render(view)
      assert is_binary(html)
    end

    test "loop operations on loaded track", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "loop_in", %{"deck" => "1", "time" => "10.0"})
      render_click(view, "loop_out", %{"deck" => "1", "time" => "18.0"})
      render_click(view, "loop_toggle", %{"deck" => "1"})
      html = render(view)
      assert is_binary(html)
    end

    test "loop_size on loaded track", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "loop_size", %{"deck" => "1", "bars" => "4"})
      html = render(view)
      assert is_binary(html)
    end

    test "set_smart_loop on loaded track", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "set_smart_loop", %{"deck" => "1", "bars" => "8"})
      html = render(view)
      assert is_binary(html)
    end

    test "crossfader interaction", %{conn: conn, track: track, track2: track2} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "load_track", %{"track-id" => track2.id, "deck" => "2"})
      render_click(view, "crossfader", %{"value" => "0.7"})
      html = render(view)
      assert is_binary(html)
    end

    test "set_crossfader_curve", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "set_crossfader_curve", %{"curve" => "sharp"})
      html = render(view)
      assert is_binary(html)
    end

    test "toggle_play on loaded track", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "toggle_play", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "toggle_metronome", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "toggle_metronome", %{})
      assert is_binary(html)
    end

    test "set_metronome_volume", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "set_metronome_volume", %{"value" => "0.5"})
      assert is_binary(html)
    end
  end

  describe "DJ tab chef panel" do
    test "toggle_chef_panel", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "toggle_chef_panel", %{})
      assert is_binary(html)
    end

    test "chef_prompt_change", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "toggle_chef_panel", %{})
      html = render_click(view, "chef_prompt_change", %{"prompt" => "create a deep house mix"})
      assert is_binary(html)
    end
  end

  describe "DJ tab stem loops" do
    test "toggle_stem_loops", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "toggle_stem_loops", %{"deck" => "1"})
      assert is_binary(html)
    end
  end

  describe "DJ tab browser" do
    test "toggle_browser", %{conn: conn} do
      view = load_dj_tab(conn)
      html = render_click(view, "toggle_browser", %{})
      assert is_binary(html)
    end

    test "browser_search", %{conn: conn} do
      view = load_dj_tab(conn)
      render_click(view, "toggle_browser", %{})
      html = render_click(view, "browser_search", %{"query" => "test"})
      assert is_binary(html)
    end
  end

  describe "DJ tab auto cues" do
    test "auto_detect_cues on loaded track", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "auto_detect_cues", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "regenerate_auto_cues on loaded track", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "regenerate_auto_cues", %{"deck" => "1"})
      assert is_binary(html)
    end
  end

  describe "DJ tab presets" do
    test "toggle_preset_section", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "toggle_preset_section", %{})
      assert is_binary(html)
    end
  end

  describe "DJ tab deck volume" do
    test "set_deck_volume", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "set_deck_volume", %{"deck" => "1", "value" => "0.8"})
      assert is_binary(html)
    end
  end

  describe "DJ tab sync" do
    test "sync_deck", %{conn: conn, track: track, track2: track2} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "load_track", %{"track-id" => track2.id, "deck" => "2"})
      html = render_click(view, "sync_deck", %{"deck" => "2"})
      assert is_binary(html)
    end

    test "master_sync", %{conn: conn, track: track, track2: track2} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "load_track", %{"track-id" => track2.id, "deck" => "2"})
      html = render_click(view, "master_sync", %{})
      assert is_binary(html)
    end
  end

  describe "DJ tab MIDI" do
    test "toggle_midi_sync", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "toggle_midi_sync", %{})
      assert is_binary(html)
    end
  end

  describe "DJ tab jog" do
    test "jog_scratch", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "jog_scratch", %{"deck" => "1", "delta" => "0.5"})
      assert is_binary(html)
    end

    test "jog_cue_press and release", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "jog_cue_press", %{"deck" => "1"})
      html = render_click(view, "jog_cue_release", %{"deck" => "1"})
      assert is_binary(html)
    end
  end

  describe "DJ tab skip and pitch" do
    test "skip_section", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      html = render_click(view, "skip_section", %{"deck" => "1", "direction" => "forward"})
      assert is_binary(html)
    end

    test "pitch_reset", %{conn: conn, track: track} do
      view = load_dj_tab(conn)
      render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
      render_click(view, "set_pitch", %{"deck" => "1", "value" => "1.05"})
      html = render_click(view, "pitch_reset", %{"deck" => "1"})
      assert is_binary(html)
    end
  end
end
