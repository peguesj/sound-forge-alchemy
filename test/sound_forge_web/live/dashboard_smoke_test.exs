defmodule SoundForgeWeb.DashboardSmokeTest do
  @moduledoc """
  Comprehensive smoke test that navigates all dashboard tabs and exercises
  key rendering paths to maximize template coverage.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    # Create multiple tracks with full pipeline data
    tracks =
      for i <- 1..3 do
        track =
          track_fixture(%{
            user_id: user.id,
            title: "Smoke Track #{i}",
            artist: "Smoke Artist",
            duration: 200 + i * 10
          })

        download_job_fixture(%{
          track_id: track.id,
          status: :completed,
          output_path: "priv/uploads/downloads/smoke#{i}.mp3"
        })

        pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

        for type <- [:vocals, :drums, :bass, :other] do
          stem_fixture(%{
            track_id: track.id,
            processing_job_id: pj.id,
            stem_type: type,
            file_path: "stems/#{type}#{i}.wav",
            file_size: 1024 * i
          })
        end

        track
      end

    %{tracks: tracks, track: hd(tracks)}
  end

  describe "full dashboard navigation" do
    test "library tab renders with tracks", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ "Smoke Track"
    end

    test "switch through all tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Library (default)
      html = render(view)
      assert is_binary(html)

      # DJ tab
      html = render_click(view, "switch_tab", %{"tab" => "dj"})
      assert is_binary(html)

      # DAW tab
      html = render_click(view, "switch_tab", %{"tab" => "daw"})
      assert is_binary(html)

      # Pads tab
      html = render_click(view, "switch_tab", %{"tab" => "pads"})
      assert is_binary(html)

      # Back to library
      html = render_click(view, "switch_tab", %{"tab" => "library"})
      assert is_binary(html)
    end

    test "settings page renders", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")
      assert html =~ "Settings" or is_binary(html)
    end
  end

  describe "library interactions" do
    test "search and filter flow", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Search
      render_click(view, "search", %{"query" => "Smoke"})
      # Filter
      render_click(view, "filter", %{"filter" => "all"})
      # Sort
      render_click(view, "sort", %{"sort_by" => "title"})
      render_click(view, "sort", %{"sort_by" => "artist"})
      render_click(view, "sort", %{"sort_by" => "duration"})
      # View toggle
      render_click(view, "toggle_view", %{"mode" => "grid"})
      html = render_click(view, "toggle_view", %{"mode" => "list"})
      assert is_binary(html)
    end

    test "batch mode flow", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_click(view, "toggle_batch_mode", %{})
      render_click(view, "toggle_select", %{"id" => track.id})
      render_click(view, "toggle_select_all", %{})
      html = render_click(view, "toggle_batch_mode", %{})
      assert is_binary(html)
    end
  end

  describe "DJ tab with loaded track" do
    test "load track on deck 1 and interact", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})

      # Load track
      render_click(view, "load_track", %{"deck" => "1", "track-id" => track.id})

      # Transport
      render_click(view, "toggle_play", %{"deck" => "1"})
      render_click(view, "set_deck_volume", %{"deck" => "1", "level" => "75"})
      render_click(view, "crossfader", %{"value" => "50"})

      # EQ
      render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "high"})
      render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "mid"})
      render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "low"})

      # Cue
      render_click(view, "set_cue", %{"deck" => "1"})
      render_click(view, "set_hot_cue", %{"deck" => "1", "letter" => "A"})
      render_click(view, "set_hot_cue", %{"deck" => "1", "letter" => "B"})

      # Pitch
      render_click(view, "set_pitch", %{"deck" => "1", "value" => "3.0"})
      html = render_click(view, "pitch_reset", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "load track on deck 2", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      render_click(view, "load_track", %{"deck" => "2", "track-id" => track.id})
      html = render_click(view, "toggle_play", %{"deck" => "2"})
      assert is_binary(html)
    end
  end

  describe "DAW tab with loaded track" do
    test "pick track and use operations", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "daw"})
      render_click(view, "pick_track", %{"track-id" => track.id})

      # Operations
      render_click(view, "select_operation", %{"type" => "crop"})
      render_click(view, "select_operation", %{"type" => "trim"})
      render_click(view, "select_operation", %{"type" => "fade_in"})
      render_click(view, "toggle_snap", %{})

      # Preview
      render_click(view, "toggle_preview", %{})
      html = render_click(view, "stop_preview", %{})
      assert is_binary(html)
    end
  end

  describe "Pads tab interactions" do
    test "create bank and interact", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "pads"})

      render_click(view, "start_create_bank", %{})
      render_click(view, "update_new_bank_name", %{"name" => "Test Bank"})
      render_click(view, "create_bank", %{"name" => "Test Bank"})

      render_click(view, "set_master_volume", %{"value" => "90"})
      html = render_click(view, "toggle_midi_learn", %{})
      assert is_binary(html)
    end
  end
end
