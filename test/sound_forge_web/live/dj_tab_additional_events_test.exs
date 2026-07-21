defmodule SoundForgeWeb.DjTabAdditionalEventsTest do
  @moduledoc """
  Tests for DJ tab handle_event clauses not covered by existing tests,
  targeting render branches with two decks loaded.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track1 =
      track_fixture(%{user_id: user.id, title: "DJ Track A", artist: "Artist A", duration: 240})

    track2 =
      track_fixture(%{user_id: user.id, title: "DJ Track B", artist: "Artist B", duration: 180})

    download_job_fixture(%{
      track_id: track1.id,
      status: :completed,
      output_path: "priv/uploads/downloads/dj_a.mp3"
    })

    download_job_fixture(%{
      track_id: track2.id,
      status: :completed,
      output_path: "priv/uploads/downloads/dj_b.mp3"
    })

    pj1 = processing_job_fixture(%{track_id: track1.id, model: "htdemucs", status: :completed})
    pj2 = processing_job_fixture(%{track_id: track2.id, model: "htdemucs", status: :completed})

    for st <- [:vocals, :drums, :bass, :other] do
      stem_fixture(%{
        track_id: track1.id,
        processing_job_id: pj1.id,
        stem_type: st,
        file_path: "stems/#{st}_a.wav",
        file_size: 1024
      })

      stem_fixture(%{
        track_id: track2.id,
        processing_job_id: pj2.id,
        stem_type: st,
        file_path: "stems/#{st}_b.wav",
        file_size: 1024
      })
    end

    %{track1: track1, track2: track2}
  end

  defp load_both_decks(conn, track1, track2) do
    {:ok, view, _html} = live(conn, ~p"/?tab=dj")
    render_click(view, "load_track", %{"track-id" => track1.id, "deck" => "1"})
    render_click(view, "load_track", %{"track-id" => track2.id, "deck" => "2"})
    view
  end

  describe "deck 2 operations" do
    test "toggle_play deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "toggle_play", %{"deck" => "2"})
      assert is_binary(html)
    end

    test "set_pitch deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "set_pitch", %{"deck" => "2", "value" => "0.95"})
      assert is_binary(html)
    end

    test "pitch_reset deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      render_click(view, "set_pitch", %{"deck" => "2", "value" => "1.05"})
      html = render_click(view, "pitch_reset", %{"deck" => "2"})
      assert is_binary(html)
    end

    test "set_deck_volume deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "set_deck_volume", %{"deck" => "2", "level" => "60"})
      assert is_binary(html)
    end

    test "toggle_eq_kill deck 2 low", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "toggle_eq_kill", %{"deck" => "2", "band" => "low"})
      assert is_binary(html)
    end

    test "loop operations on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      render_click(view, "loop_in", %{"deck" => "2"})
      render_click(view, "loop_out", %{"deck" => "2"})
      html = render_click(view, "loop_toggle", %{"deck" => "2"})
      assert is_binary(html)
    end

    test "loop_size on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "loop_size", %{"deck" => "2", "beats" => "8"})
      assert is_binary(html)
    end

    test "set_cue on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "set_cue", %{"deck" => "2"})
      assert is_binary(html)
    end

    test "set_hot_cue on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "set_hot_cue", %{"deck" => "2", "letter" => "C"})
      assert is_binary(html)
    end

    test "jog_scratch on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "jog_scratch", %{"deck" => "2", "delta" => "-0.3"})
      assert is_binary(html)
    end

    test "skip_section forward on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "skip_section", %{"deck" => "2", "direction" => "forward"})
      assert is_binary(html)
    end

    test "time_update on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "time_update", %{"deck" => "2", "position" => "45.0"})
      assert is_binary(html)
    end

    test "deck_stopped on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "deck_stopped", %{"deck" => "2"})
      assert is_binary(html)
    end

    test "set_filter highpass on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)

      html =
        render_click(view, "set_filter", %{"deck" => "2", "mode" => "highpass", "cutoff" => "0.7"})

      assert is_binary(html)
    end

    test "set_time_factor on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "set_time_factor", %{"deck" => "2", "factor" => "2.0"})
      assert is_binary(html)
    end

    test "auto_detect_cues on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "auto_detect_cues", %{"deck" => "2"})
      assert is_binary(html)
    end

    test "toggle_stem_loops on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "toggle_stem_loops", %{"deck" => "2"})
      assert is_binary(html)
    end
  end

  describe "sync operations with both decks" do
    test "sync_deck deck 1 to 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "sync_deck", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "toggle_midi_sync deck 1", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "toggle_midi_sync", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "toggle_midi_sync deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "toggle_midi_sync", %{"deck" => "2"})
      assert is_binary(html)
    end
  end

  describe "crossfader with both decks" do
    test "crossfader full left", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "crossfader", %{"value" => "0.0"})
      assert is_binary(html)
    end

    test "crossfader full right", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "crossfader", %{"value" => "1.0"})
      assert is_binary(html)
    end

    test "set_crossfader_curve linear", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "set_crossfader_curve", %{"curve" => "linear"})
      assert is_binary(html)
    end

    test "set_crossfader_curve smooth", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      html = render_click(view, "set_crossfader_curve", %{"curve" => "smooth"})
      assert is_binary(html)
    end
  end

  describe "browser_search on DJ tab" do
    test "browser_search with query", %{conn: conn, track1: t1, track2: t2} do
      view = load_both_decks(conn, t1, t2)
      render_click(view, "toggle_browser", %{})
      html = render_click(view, "browser_search", %{"value" => "Artist"})
      assert is_binary(html)
    end
  end
end
