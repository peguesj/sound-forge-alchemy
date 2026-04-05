defmodule SoundForgeWeb.DjDeckLoadedTest do
  @moduledoc """
  Tests for DJ tab with tracks loaded on decks to exercise template branches
  that render deck state (waveform, play/pause, BPM display, cue points, etc.)
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  defp load_track_on_deck(view, track, deck) do
    render_click(view, "load_track", %{"track_id" => track.id, "deck" => deck})
  end

  describe "single deck loaded" do
    test "load track on deck 1 then play/pause", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Loaded A", duration: 200})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      load_track_on_deck(view, track, "1")
      html = render_click(view, "toggle_play", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "load track then set cue", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Cue A", duration: 180})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      load_track_on_deck(view, track, "1")
      html = render_click(view, "set_cue", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "load track then loop_in and loop_out", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Loop A", duration: 240})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      load_track_on_deck(view, track, "1")
      render_click(view, "loop_in", %{"deck" => "1"})
      html = render_click(view, "loop_out", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "load track then set pitch and pitch_reset", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Pitch A", duration: 200})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      load_track_on_deck(view, track, "1")
      render_click(view, "set_pitch", %{"deck" => "1", "value" => "4.0"})
      html = render_click(view, "pitch_reset", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "load track then EQ kills on all bands", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "EQ A", duration: 180})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      load_track_on_deck(view, track, "1")

      for band <- ["low", "mid", "high"] do
        html = render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => band})
        assert html =~ "dj-tab"
      end
    end

    test "load track on deck 2 then control it", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Deck 2 Track", duration: 220})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      load_track_on_deck(view, track, "2")
      render_click(view, "toggle_play", %{"deck" => "2"})
      html = render_click(view, "set_deck_volume", %{"deck" => "2", "level" => "80"})
      assert html =~ "dj-tab"
    end
  end

  describe "both decks loaded" do
    test "load tracks on both decks then crossfade", %{conn: conn, user: user} do
      track_a = track_fixture(%{user_id: user.id, title: "Left A", duration: 200})
      track_b = track_fixture(%{user_id: user.id, title: "Right B", duration: 180})
      {:ok, view, _html} = live(conn, "/?tab=dj")

      load_track_on_deck(view, track_a, "1")
      load_track_on_deck(view, track_b, "2")

      render_click(view, "toggle_play", %{"deck" => "1"})
      render_click(view, "toggle_play", %{"deck" => "2"})

      html = render_click(view, "crossfader", %{"value" => "75"})
      assert html =~ "dj-tab"
    end

    test "sync deck 2 to deck 1", %{conn: conn, user: user} do
      track_a = track_fixture(%{user_id: user.id, title: "Master", duration: 200})
      track_b = track_fixture(%{user_id: user.id, title: "Sync", duration: 180})
      {:ok, view, _html} = live(conn, "/?tab=dj")

      load_track_on_deck(view, track_a, "1")
      load_track_on_deck(view, track_b, "2")

      html = render_click(view, "sync_deck", %{"deck" => "2"})
      assert html =~ "dj-tab"
    end

    test "master_sync with both decks loaded", %{conn: conn, user: user} do
      track_a = track_fixture(%{user_id: user.id, title: "Track MA", duration: 200})
      track_b = track_fixture(%{user_id: user.id, title: "Track MB", duration: 180})
      {:ok, view, _html} = live(conn, "/?tab=dj")

      load_track_on_deck(view, track_a, "1")
      load_track_on_deck(view, track_b, "2")

      html = render_click(view, "master_sync")
      assert html =~ "dj-tab"
    end
  end

  describe "deck with stems" do
    test "load stemmed track and control stems", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Stemmed", duration: 240})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

      for type <- [:vocals, :drums, :bass, :other] do
        stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: type})
      end

      {:ok, view, _html} = live(conn, "/?tab=dj")
      load_track_on_deck(view, track, "1")

      # Toggle stem mute
      html = render_click(view, "toggle_stem_mute", %{"deck" => "1", "stem" => "vocals"})
      assert html =~ "dj-tab"

      # Toggle stem solo
      html = render_click(view, "toggle_stem_solo", %{"deck" => "1", "stem" => "drums"})
      assert html =~ "dj-tab"

      # Stem volume
      html = render_click(view, "stem_volume", %{"deck" => "1", "stem" => "bass", "value" => "50"})
      assert html =~ "dj-tab"
    end
  end

  describe "time factor" do
    test "set_time_factor", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Time Factor"})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      load_track_on_deck(view, track, "1")
      html = render_click(view, "set_time_factor", %{"deck" => "1", "factor" => "0.5"})
      assert html =~ "dj-tab"
    end
  end

  describe "loop sizes" do
    test "loop_size with various beat counts", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Loop Sizes"})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      load_track_on_deck(view, track, "1")

      for beats <- ["1", "2", "4", "8", "16"] do
        html = render_click(view, "loop_size", %{"deck" => "1", "beats" => beats})
        assert html =~ "dj-tab"
      end
    end
  end

  describe "filter modes" do
    test "all filter modes", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Filtered"})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      load_track_on_deck(view, track, "1")

      for mode <- ["lowpass", "highpass", "bandpass", "off"] do
        html = render_click(view, "set_filter", %{"deck" => "1", "mode" => mode, "cutoff" => "0.5"})
        assert html =~ "dj-tab"
      end
    end
  end
end
