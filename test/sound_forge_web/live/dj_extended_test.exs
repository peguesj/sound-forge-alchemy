defmodule SoundForgeWeb.DjExtendedTest do
  @moduledoc """
  Extended DJ tab tests exercising more template branches: metronome, chef panel,
  cue management, stem loops, time factors, EQ kills, filter modes, preset section.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "metronome" do
    test "toggle_metronome", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_metronome")
      assert html =~ "dj-tab"
    end

    test "set_metronome_volume", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_metronome_volume", %{"volume" => "50"})
      assert html =~ "dj-tab"
    end
  end

  describe "chef panel" do
    test "toggle_chef_panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_chef_panel")
      assert html =~ "dj-tab"
    end

    test "chef_prompt_change", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "toggle_chef_panel")
      html = render_click(view, "chef_prompt_change", %{"prompt" => "deep house set"})
      assert html =~ "dj-tab"
    end

    test "chef_cook with no tracks", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "toggle_chef_panel")
      render_click(view, "chef_prompt_change", %{"prompt" => "chill vibes"})
      html = render_click(view, "chef_cook")
      assert html =~ "dj-tab"
    end
  end

  describe "preset section" do
    test "toggle_preset_section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_preset_section")
      assert html =~ "dj-tab"
    end

    test "validate_preset", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "validate_preset")
      assert html =~ "dj-tab"
    end
  end

  describe "cue operations" do
    test "set_cue on deck 1", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Cue Track"})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})
      html = render_click(view, "set_cue", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "set_cue on deck 2", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Cue Track 2"})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "2"})
      html = render_click(view, "set_cue", %{"deck" => "2"})
      assert html =~ "dj-tab"
    end
  end

  describe "EQ and filter" do
    test "toggle_eq_kill low", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "low"})
      assert html =~ "dj-tab"
    end

    test "toggle_eq_kill mid", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "mid"})
      assert html =~ "dj-tab"
    end

    test "toggle_eq_kill high", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "high"})
      assert html =~ "dj-tab"
    end

    test "set_filter lowpass", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_filter", %{"deck" => "1", "mode" => "lowpass", "cutoff" => "0.5"})
      assert html =~ "dj-tab"
    end

    test "set_filter highpass", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_filter", %{"deck" => "1", "mode" => "highpass", "cutoff" => "0.3"})
      assert html =~ "dj-tab"
    end

    test "set_filter off", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_filter", %{"deck" => "1", "mode" => "off", "cutoff" => "0"})
      assert html =~ "dj-tab"
    end
  end

  describe "pitch and sync" do
    test "set_pitch on deck 1", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_pitch", %{"deck" => "1", "value" => "3.5"})
      assert html =~ "dj-tab"
    end

    test "set_pitch on deck 2", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_pitch", %{"deck" => "2", "value" => "-2.0"})
      assert html =~ "dj-tab"
    end

    test "pitch_reset", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "pitch_reset", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "sync_deck", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "sync_deck", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "master_sync", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "master_sync")
      assert html =~ "dj-tab"
    end
  end

  describe "loop operations" do
    test "loop_in", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "loop_in", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "loop_out", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "loop_out", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "loop_size 4 beats", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "loop_size", %{"deck" => "1", "beats" => "4"})
      assert html =~ "dj-tab"
    end

    test "loop_size 8 beats", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "loop_size", %{"deck" => "1", "beats" => "8"})
      assert html =~ "dj-tab"
    end

    test "loop_toggle", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "loop_toggle", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end
  end

  describe "jog and transport" do
    test "jog_scratch positive", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "jog_scratch", %{"deck" => "1", "delta" => "5"})
      assert html =~ "dj-tab"
    end

    test "jog_scratch negative", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "jog_scratch", %{"deck" => "2", "delta" => "-3"})
      assert html =~ "dj-tab"
    end

    test "jog_cue_press", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "jog_cue_press", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "jog_cue_release", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "jog_cue_release", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "skip_section forward", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "skip_section", %{"deck" => "1", "direction" => "forward"})
      assert html =~ "dj-tab"
    end

    test "skip_section backward", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "skip_section", %{"deck" => "1", "direction" => "backward"})
      assert html =~ "dj-tab"
    end

    test "time_update", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "time_update", %{"deck" => "1", "position" => "60.0"})
      assert html =~ "dj-tab"
    end

    test "deck_stopped", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "deck_stopped", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end
  end

  describe "crossfader" do
    test "crossfader at center", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "crossfader", %{"value" => "50"})
      assert html =~ "dj-tab"
    end

    test "crossfader at left extreme", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "crossfader", %{"value" => "0"})
      assert html =~ "dj-tab"
    end

    test "crossfader at right extreme", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "crossfader", %{"value" => "100"})
      assert html =~ "dj-tab"
    end

    test "set_crossfader_curve smooth", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_crossfader_curve", %{"curve" => "smooth"})
      assert html =~ "dj-tab"
    end

    test "set_crossfader_curve sharp", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_crossfader_curve", %{"curve" => "sharp"})
      assert html =~ "dj-tab"
    end

    test "set_crossfader_curve linear", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_crossfader_curve", %{"curve" => "linear"})
      assert html =~ "dj-tab"
    end
  end

  describe "volume" do
    test "set_deck_volume deck 1", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_deck_volume", %{"deck" => "1", "level" => "75"})
      assert html =~ "dj-tab"
    end

    test "set_deck_volume deck 2", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_deck_volume", %{"deck" => "2", "level" => "50"})
      assert html =~ "dj-tab"
    end

    test "set_deck_volume zero", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_deck_volume", %{"deck" => "1", "level" => "0"})
      assert html =~ "dj-tab"
    end

    test "set_deck_volume max", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_deck_volume", %{"deck" => "1", "level" => "100"})
      assert html =~ "dj-tab"
    end
  end

  describe "stem loops" do
    test "toggle_stem_loops", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_stem_loops", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end
  end

  describe "browser" do
    test "toggle_browser", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_browser")
      assert html =~ "dj-tab"
    end

    test "browser_search", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "browser_search", %{"value" => "test search"})
      assert html =~ "dj-tab"
    end
  end

  describe "midi sync" do
    test "toggle_midi_sync deck 1", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_midi_sync", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "toggle_midi_sync deck 2", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_midi_sync", %{"deck" => "2"})
      assert html =~ "dj-tab"
    end
  end
end
