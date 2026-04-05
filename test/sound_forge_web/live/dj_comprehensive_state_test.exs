defmodule SoundForgeWeb.DjComprehensiveStateTest do
  @moduledoc """
  Tests exercising DJ tab with various state combinations to increase
  template coverage: analyzed tracks on decks, chef recipe rendering,
  metronome state, effects state, etc.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  defp create_analyzed_track(user, title, opts \\ %{}) do
    track = track_fixture(Map.merge(%{user_id: user.id, title: title, duration: 200}, opts))
    download_job_fixture(%{track_id: track.id, status: :completed, output_path: "/tmp/#{title}.mp3"})
    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    for type <- [:vocals, :drums, :bass, :other] do
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: type})
    end

    aj = analysis_job_fixture(%{track_id: track.id, status: :completed})
    analysis_result_fixture(Map.merge(%{
      track_id: track.id,
      analysis_job_id: aj.id,
      tempo: 128.0,
      key: "A minor",
      energy: 0.85
    }, opts))
    track
  end

  describe "DJ with analyzed tracks on both decks" do
    test "load analyzed tracks and crossfade", %{conn: conn, user: user} do
      t1 = create_analyzed_track(user, "Deck1 Track", %{tempo: 126.0, key: "C major"})
      t2 = create_analyzed_track(user, "Deck2 Track", %{tempo: 128.0, key: "A minor"})

      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => t1.id, "deck" => "1"})
      render_click(view, "load_track", %{"track_id" => t2.id, "deck" => "2"})
      render_click(view, "toggle_play", %{"deck" => "1"})
      render_click(view, "toggle_play", %{"deck" => "2"})

      html = render_click(view, "crossfader", %{"value" => "50"})
      assert html =~ "dj-tab"
    end

    test "load track then apply all EQ bands and filter", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "EQ Track")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})

      # EQ kills
      render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "low"})
      render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "mid"})
      render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "high"})

      # Filter
      render_click(view, "set_filter", %{"deck" => "1", "mode" => "lowpass", "cutoff" => "0.3"})
      html = render_click(view, "set_filter", %{"deck" => "1", "mode" => "highpass", "cutoff" => "0.7"})
      assert html =~ "dj-tab"
    end

    test "load track then set various pitch values", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "Pitch Track")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})

      for pitch <- ["-8.0", "-4.0", "0.0", "4.0", "8.0"] do
        html = render_click(view, "set_pitch", %{"deck" => "1", "value" => pitch})
        assert html =~ "dj-tab"
      end
    end

    test "load tracks and use jog operations", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "Jog Track")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})

      render_click(view, "jog_scratch", %{"deck" => "1", "delta" => "5.0"})
      render_click(view, "jog_scratch", %{"deck" => "1", "delta" => "-5.0"})
      render_click(view, "jog_cue_press", %{"deck" => "1"})
      html = render_click(view, "jog_cue_release", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "load track and skip sections", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "Skip Track")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})

      html = render_click(view, "skip_section", %{"deck" => "1", "direction" => "forward"})
      assert html =~ "dj-tab"
      html2 = render_click(view, "skip_section", %{"deck" => "1", "direction" => "backward"})
      assert html2 =~ "dj-tab"
    end
  end

  describe "DJ metronome with loaded track" do
    test "toggle metronome and set volume", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "Metro Track")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})

      render_click(view, "toggle_metronome")
      html = render_click(view, "metronome_volume", %{"value" => "60"})
      assert html =~ "dj-tab"
    end
  end

  describe "DJ crossfader curves" do
    test "all crossfader curve types", %{conn: conn, user: user} do
      t1 = create_analyzed_track(user, "Curve A")
      t2 = create_analyzed_track(user, "Curve B")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => t1.id, "deck" => "1"})
      render_click(view, "load_track", %{"track_id" => t2.id, "deck" => "2"})

      for curve <- ["smooth", "sharp", "linear"] do
        html = render_click(view, "crossfader_curve", %{"curve" => curve})
        assert html =~ "dj-tab"
      end
    end
  end

  describe "DJ deck volume extremes" do
    test "volume at 0 and 100", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "Vol Track")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})

      html = render_click(view, "set_deck_volume", %{"deck" => "1", "level" => "0"})
      assert html =~ "dj-tab"
      html2 = render_click(view, "set_deck_volume", %{"deck" => "1", "level" => "100"})
      assert html2 =~ "dj-tab"
    end
  end

  describe "DJ stem controls with analyzed tracks" do
    test "mute and solo stems on loaded analyzed track", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "Stem Control")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})

      # Mute each stem
      for stem <- ["vocals", "drums", "bass", "other"] do
        html = render_click(view, "toggle_stem_mute", %{"deck" => "1", "stem" => stem})
        assert html =~ "dj-tab"
      end

      # Solo a stem
      html = render_click(view, "toggle_stem_solo", %{"deck" => "1", "stem" => "vocals"})
      assert html =~ "dj-tab"

      # Unsolo
      html2 = render_click(view, "toggle_stem_solo", %{"deck" => "1", "stem" => "vocals"})
      assert html2 =~ "dj-tab"
    end

    test "set stem volumes", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "Stem Vol")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})

      for stem <- ["vocals", "drums", "bass", "other"] do
        html = render_click(view, "stem_volume", %{"deck" => "1", "stem" => stem, "value" => "50"})
        assert html =~ "dj-tab"
      end
    end
  end

  describe "DJ time updates" do
    test "time_update on playing deck", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "Time Track")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})
      render_click(view, "toggle_play", %{"deck" => "1"})

      html = render_click(view, "time_update", %{"deck" => "1", "time" => "45.5", "duration" => "200"})
      assert html =~ "dj-tab"
    end

    test "deck_stopped event", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "Stop Track")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})
      render_click(view, "toggle_play", %{"deck" => "1"})
      html = render_click(view, "deck_stopped", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end
  end

  describe "DJ browser" do
    test "toggle browser, search, and select", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "Browse Track"})
      {:ok, view, _html} = live(conn, "/?tab=dj")

      render_click(view, "toggle_browser")
      render_click(view, "browser_search", %{"value" => "Browse"})
      html = render_click(view, "toggle_browser")
      assert html =~ "dj-tab"
    end
  end

  describe "DJ loop operations with loaded track" do
    test "loop_in and loop_out on analyzed track", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "Loop Track")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})
      render_click(view, "toggle_play", %{"deck" => "1"})

      render_click(view, "loop_in", %{"deck" => "1"})
      render_click(view, "loop_out", %{"deck" => "1"})
      html = render_click(view, "loop_toggle", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "loop_size with various beats", %{conn: conn, user: user} do
      track = create_analyzed_track(user, "Beat Loop")
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})

      for beats <- ["1", "2", "4", "8", "16", "32"] do
        html = render_click(view, "loop_size", %{"deck" => "1", "beats" => beats})
        assert html =~ "dj-tab"
      end
    end
  end
end
