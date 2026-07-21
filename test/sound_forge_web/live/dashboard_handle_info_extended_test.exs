defmodule SoundForgeWeb.DashboardHandleInfoExtendedTest do
  @moduledoc """
  Tests for DashboardLive handle_info patterns that are not covered by
  existing test files: spotify_metadata, broadcast events, MIDI actions,
  virtual controller, chef events, and auto_cue completion.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "HandleInfo Track",
        artist: "Test Artist",
        duration: 200,
        spotify_url: "https://open.spotify.com/track/info123"
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/info_test.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    stem_fixture(%{
      track_id: track.id,
      processing_job_id: pj.id,
      stem_type: :vocals,
      file_path: "stems/vocals.wav",
      file_size: 1024
    })

    %{track: track}
  end

  describe "spotify_metadata handle_info" do
    test "handles spotify_metadata error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:spotify_metadata, "https://open.spotify.com/track/test", {:error, :not_found}}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "handles spotify_metadata with track data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      tracks_data = [
        %{
          "title" => "Imported Track",
          "artist" => "Test Artist",
          "spotify_url" => "https://open.spotify.com/track/abc",
          "album" => "Test Album",
          "duration" => 180
        }
      ]

      send(
        view.pid,
        {:spotify_metadata, "https://open.spotify.com/track/abc", {:ok, tracks_data}}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "handles spotify_metadata with playlist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      tracks_data = [
        %{
          "title" => "Track 1",
          "artist" => "Artist 1",
          "spotify_url" => "https://open.spotify.com/track/1",
          "duration" => 200
        },
        %{
          "title" => "Track 2",
          "artist" => "Artist 2",
          "spotify_url" => "https://open.spotify.com/track/2",
          "duration" => 180
        }
      ]

      playlist_meta = %{"name" => "Test Playlist", "total" => 2}

      send(
        view.pid,
        {:spotify_metadata, "https://open.spotify.com/playlist/xyz",
         {:ok, tracks_data, playlist_meta}}
      )

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "broadcast events" do
    test "handles auto_cues_complete broadcast", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track:#{track.id}")

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "track:#{track.id}",
        event: "auto_cues_complete",
        payload: %{track_id: track.id, cue_count: 4}
      })

      html = render(view)
      assert is_binary(html)
    end

    test "handles chef_progress broadcast", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "track:#{track.id}",
        event: "chef_progress",
        payload: %{track_id: track.id, progress: 50, message: "Processing stems..."}
      })

      html = render(view)
      assert is_binary(html)
    end

    test "handles chef_complete broadcast", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "track:#{track.id}",
        event: "chef_complete",
        payload: %{track_id: track.id, recipe_id: "recipe-1"}
      })

      html = render(view)
      assert is_binary(html)
    end

    test "handles chef_failed broadcast", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "track:#{track.id}",
        event: "chef_failed",
        payload: %{track_id: track.id, error: "All tracks exhausted"}
      })

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "MIDI and virtual controller handle_info" do
    test "handles midi_action trigger_cue via midi_action", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:midi_action, :trigger_cue, %{deck: 1, cue_index: 0}})
      html = render(view)
      assert is_binary(html)
    end

    test "handles midi_action stem_volume", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:midi_action, :stem_volume, %{deck: 1, stem: "vocals", value: 0.8}})
      html = render(view)
      assert is_binary(html)
    end

    test "handles midi_action generic", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:midi_action, :unknown_action, %{value: 1}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "task completion" do
    test "handles task ref completion", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      ref = make_ref()
      send(view.pid, {ref, :ok})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "pipeline_complete for specific stages" do
    test "handles pipeline_complete with all stages", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:pipeline_complete, %{track_id: track.id}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "batch events" do
    test "handles batch_progress", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:batch_progress,
         %{batch_job_id: "job-1", status: :processing, completed_count: 1, total_count: 5}}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "handles batch_complete", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:batch_complete,
         %{batch_job_id: "job-1", completed_count: 5, failed_count: 0, total_count: 5}}
      )

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "debug_log" do
    test "handles debug_log message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:debug_log,
         %{level: :info, message: "Test log", namespace: "test", timestamp: DateTime.utc_now()}}
      )

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "bpm_update" do
    test "handles bpm_update", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:bpm_update, %{bpm: 128.0, source: "manual"}})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "transport" do
    test "handles transport play", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:transport, :play})
      html = render(view)
      assert is_binary(html)
    end

    test "handles transport stop", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:transport, :stop})
      html = render(view)
      assert is_binary(html)
    end
  end
end
