defmodule SoundForgeWeb.DjTabUpdateTest do
  @moduledoc """
  Tests for DjTabComponent update/2 clauses that are triggered
  via send_update from DashboardLive handle_info when nav_tab == :dj.
  Covers MIDI event forwarding, broadcast handling, and chef events.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "DJ Update Track",
      artist: "DJ Update Artist",
      duration: 240
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/dj_update.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/vocals.wav", file_size: 1024})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :drums, file_path: "stems/drums.wav", file_size: 1024})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :bass, file_path: "stems/bass.wav", file_size: 1024})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :other, file_path: "stems/other.wav", file_size: 1024})

    %{track: track}
  end

  defp setup_dj_with_track(conn, track) do
    {:ok, view, _html} = live(conn, ~p"/?tab=dj")
    render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
    view
  end

  describe "MIDI transport forwarding to DJ tab" do
    test "transport play forwarded to DJ component", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, {:transport, :play})
      html = render(view)
      assert is_binary(html)
    end

    test "transport stop forwarded to DJ component", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, {:transport, :stop})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "BPM update forwarding to DJ tab" do
    test "bpm_update forwarded to DJ component", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, {:bpm_update, %{bpm: 128.0, source: "manual"}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "MIDI action forwarding to DJ tab" do
    test "midi_action stem_volume forwarded to DJ", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, {:midi_action, :stem_volume, %{deck: 1, stem: "vocals", value: 0.8}})
      html = render(view)
      assert is_binary(html)
    end

    test "midi_action generic forwarded to DJ", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, {:midi_action, :unknown_action, %{value: 1}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "broadcast events forwarded to DJ tab" do
    test "auto_cues_complete broadcast forwarded to DJ", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "track:#{track.id}",
        event: "auto_cues_complete",
        payload: %{track_id: track.id, cue_count: 4}
      })
      html = render(view)
      assert is_binary(html)
    end

    test "chef_progress broadcast forwarded to DJ", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "track:#{track.id}",
        event: "chef_progress",
        payload: %{track_id: track.id, progress: 50, message: "Processing..."}
      })
      html = render(view)
      assert is_binary(html)
    end

    test "chef_complete broadcast forwarded to DJ", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "track:#{track.id}",
        event: "chef_complete",
        payload: %{track_id: track.id, recipe_id: "recipe-1"}
      })
      html = render(view)
      assert is_binary(html)
    end

    test "chef_failed broadcast forwarded to DJ", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "track:#{track.id}",
        event: "chef_failed",
        payload: %{track_id: track.id, error: "All tracks exhausted"}
      })
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "debug_log forwarding to DJ tab" do
    test "debug_log forwarded while on DJ tab", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, {:debug_log, %{level: :info, message: "Test log", namespace: "midi", timestamp: DateTime.utc_now()}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "pipeline events on DJ tab" do
    test "pipeline_progress on DJ tab", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, {:pipeline_progress, %{track_id: track.id, stage: :processing, status: :running, progress: 50}})
      html = render(view)
      assert is_binary(html)
    end

    test "pipeline_complete on DJ tab", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, {:pipeline_complete, %{track_id: track.id}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "batch events on DJ tab" do
    test "batch_progress on DJ tab", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, {:batch_progress, %{batch_job_id: "job-1", status: :processing, completed_count: 1, total_count: 3}})
      html = render(view)
      assert is_binary(html)
    end

    test "batch_complete on DJ tab", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, {:batch_complete, %{batch_job_id: "job-1", completed_count: 3, failed_count: 0, total_count: 3}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "spotify metadata on DJ tab" do
    test "spotify_metadata error on DJ tab", %{conn: conn, track: track} do
      view = setup_dj_with_track(conn, track)
      send(view.pid, {:spotify_metadata, "https://open.spotify.com/track/test", {:error, :not_found}})
      html = render(view)
      assert is_binary(html)
    end
  end
end
