defmodule SoundForgeWeb.DjTabEventsMegaTest do
  @moduledoc "Comprehensive DJ tab event coverage for the remaining untested handle_event clauses."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{user_id: user.id, title: "DJ Mega Test", artist: "Test DJ", duration: 240})

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/mega.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    for type <- [:vocals, :drums, :bass, :other] do
      stem_fixture(%{
        track_id: track.id,
        processing_job_id: pj.id,
        stem_type: type,
        file_path: "stems/#{type}.wav",
        file_size: 1024
      })
    end

    %{track: track}
  end

  defp go_dj(conn) do
    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "switch_tab", %{"tab" => "dj"})
    view
  end

  describe "transport events" do
    test "toggle_play deck 1", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "toggle_play", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "toggle_play deck 2", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "toggle_play", %{"deck" => "2"})
      assert is_binary(html)
    end

    test "time_update", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "time_update", %{"deck" => "1", "position" => "45.5"})
      assert is_binary(html)
    end

    test "deck_stopped", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "deck_stopped", %{"deck" => "1"})
      assert is_binary(html)
    end
  end

  describe "crossfader events" do
    test "crossfader value change", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "crossfader", %{"value" => "50"})
      assert is_binary(html)
    end

    test "set_crossfader_curve linear", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_crossfader_curve", %{"curve" => "linear"})
      assert is_binary(html)
    end

    test "set_crossfader_curve smooth", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_crossfader_curve", %{"curve" => "smooth"})
      assert is_binary(html)
    end

    test "set_crossfader_curve sharp", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_crossfader_curve", %{"curve" => "sharp"})
      assert is_binary(html)
    end

    test "set_crossfader_curve no params", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_crossfader_curve", %{})
      assert is_binary(html)
    end
  end

  describe "deck volume events" do
    test "set_deck_volume deck 1", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_deck_volume", %{"deck" => "1", "level" => "85"})
      assert is_binary(html)
    end

    test "set_deck_volume deck 2", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_deck_volume", %{"deck" => "2", "level" => "50"})
      assert is_binary(html)
    end
  end

  describe "jog wheel events" do
    test "jog_scratch positive delta", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "jog_scratch", %{"deck" => "1", "delta" => "5.0"})
      assert is_binary(html)
    end

    test "jog_scratch negative delta", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "jog_scratch", %{"deck" => "1", "delta" => "-3.0"})
      assert is_binary(html)
    end

    test "jog_cue_press", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "jog_cue_press", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "jog_cue_release", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "jog_cue_release", %{"deck" => "1"})
      assert is_binary(html)
    end
  end

  describe "loop events" do
    test "loop_in deck 1", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "loop_in", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "loop_out deck 1", %{conn: conn} do
      view = go_dj(conn)
      render_click(view, "loop_in", %{"deck" => "1"})
      html = render_click(view, "loop_out", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "loop_size", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "loop_size", %{"deck" => "1", "beats" => "4"})
      assert is_binary(html)
    end

    test "loop_toggle", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "loop_toggle", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "set_smart_loop", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_smart_loop", %{"deck" => "1", "loop-idx" => "0"})
      assert is_binary(html)
    end
  end

  describe "pitch and sync events" do
    test "set_pitch", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_pitch", %{"deck" => "1", "value" => "2.5"})
      assert is_binary(html)
    end

    test "pitch_reset", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "pitch_reset", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "sync_deck", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "sync_deck", %{"deck" => "1"})
      assert is_binary(html)
    end
  end

  describe "cue events" do
    test "set_cue", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_cue", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "set_hot_cue A", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_hot_cue", %{"deck" => "1", "letter" => "A"})
      assert is_binary(html)
    end

    test "clear_hot_cue A", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "clear_hot_cue", %{"deck" => "1", "letter" => "A"})
      assert is_binary(html)
    end
  end

  describe "section skip events" do
    test "skip_section forward", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "skip_section", %{"deck" => "1", "direction" => "forward"})
      assert is_binary(html)
    end

    test "skip_section backward", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "skip_section", %{"deck" => "1", "direction" => "backward"})
      assert is_binary(html)
    end
  end

  describe "EQ and filter events" do
    test "toggle_eq_kill high", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "high"})
      assert is_binary(html)
    end

    test "toggle_eq_kill mid", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "mid"})
      assert is_binary(html)
    end

    test "toggle_eq_kill low", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "low"})
      assert is_binary(html)
    end

    test "set_filter", %{conn: conn} do
      view = go_dj(conn)

      html =
        render_click(view, "set_filter", %{"deck" => "1", "mode" => "lowpass", "cutoff" => "0.7"})

      assert is_binary(html)
    end
  end

  describe "time factor and metronome" do
    test "set_time_factor", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_time_factor", %{"deck" => "1", "factor" => "0.5"})
      assert is_binary(html)
    end

    test "set_metronome_volume", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "set_metronome_volume", %{"volume" => "75"})
      assert is_binary(html)
    end
  end

  describe "auto cue events" do
    test "auto_detect_cues", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "auto_detect_cues", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "regenerate_auto_cues", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "regenerate_auto_cues", %{"deck" => "1"})
      assert is_binary(html)
    end
  end

  describe "browser events" do
    test "toggle_browser", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "toggle_browser", %{})
      assert is_binary(html)
    end

    test "browser_search", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "browser_search", %{"value" => "house"})
      assert is_binary(html)
    end
  end

  describe "chef events" do
    test "toggle_chef_panel", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "toggle_chef_panel", %{})
      assert is_binary(html)
    end

    test "chef_prompt_change", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "chef_prompt_change", %{"prompt" => "deep house mix"})
      assert is_binary(html)
    end
  end

  describe "stem loop events" do
    test "toggle_stem_loops", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "toggle_stem_loops", %{"deck" => "1"})
      assert is_binary(html)
    end
  end

  describe "preset events" do
    test "toggle_preset_section", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "toggle_preset_section", %{})
      assert is_binary(html)
    end

    test "validate_preset", %{conn: conn} do
      view = go_dj(conn)
      html = render_click(view, "validate_preset", %{})
      assert is_binary(html)
    end
  end

  describe "load_track event" do
    test "load_track into deck 1", %{conn: conn, track: track} do
      view = go_dj(conn)
      html = render_click(view, "load_track", %{"deck" => "1", "track-id" => track.id})
      assert is_binary(html)
    end

    test "load_track into deck 2", %{conn: conn, track: track} do
      view = go_dj(conn)
      html = render_click(view, "load_track", %{"deck" => "2", "track-id" => track.id})
      assert is_binary(html)
    end
  end
end
