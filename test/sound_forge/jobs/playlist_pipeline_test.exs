defmodule SoundForge.Jobs.PlaylistPipelineTest do
  @moduledoc """
  Tests for playlist pipeline alignment features:
  - Music.get_track_by_spotify_id_with_status/1
  - Music.list_playlist_tracks_with_status/1
  - Music.track_pipeline_complete?/1
  - PipelineBroadcaster.broadcast_playlist_track_update/3
  """
  use SoundForge.DataCase

  import SoundForge.MusicFixtures
  import SoundForge.AccountsFixtures

  alias SoundForge.Jobs.PipelineBroadcaster
  alias SoundForge.Music

  setup do
    user = user_fixture()
    track = track_fixture(%{
      user_id: user.id,
      title: "Pipeline Test Track",
      artist: "Test Artist",
      spotify_id: "sp_test_#{System.unique_integer([:positive])}",
      spotify_url: "https://open.spotify.com/track/test_#{System.unique_integer([:positive])}",
      duration: 200
    })
    %{user: user, track: track}
  end

  # ---------------------------------------------------------------------------
  # get_track_by_spotify_id_with_status/1
  # ---------------------------------------------------------------------------

  describe "Music.get_track_by_spotify_id_with_status/1" do
    test "returns nil when spotify_id not found", %{} do
      assert nil == Music.get_track_by_spotify_id_with_status("nonexistent_id")
    end

    test "returns nil when spotify_id is nil", %{} do
      assert nil == Music.get_track_by_spotify_id_with_status(nil)
    end

    test "returns track with preloaded job associations", %{track: track} do
      result = Music.get_track_by_spotify_id_with_status(track.spotify_id)
      assert result.id == track.id
      assert is_list(result.download_jobs)
      assert is_list(result.processing_jobs)
      assert is_list(result.analysis_jobs)
    end

    test "includes associated download jobs in result", %{track: track} do
      download_job_fixture(%{track_id: track.id, status: :completed})
      result = Music.get_track_by_spotify_id_with_status(track.spotify_id)
      assert length(result.download_jobs) == 1
      assert hd(result.download_jobs).status == :completed
    end
  end

  # ---------------------------------------------------------------------------
  # list_playlist_tracks_with_status/1
  # ---------------------------------------------------------------------------

  describe "Music.list_playlist_tracks_with_status/1" do
    test "returns empty list for empty playlist", %{user: user} do
      playlist = playlist_fixture(%{user_id: user.id})
      assert [] == Music.list_playlist_tracks_with_status(playlist.id)
    end

    test "returns tracks with preloaded job associations", %{user: user, track: track} do
      playlist = playlist_fixture(%{user_id: user.id})
      Music.add_track_to_playlist(playlist, track, 0)

      results = Music.list_playlist_tracks_with_status(playlist.id)
      assert length(results) == 1
      result = hd(results)
      assert result.id == track.id
      assert is_list(result.download_jobs)
      assert is_list(result.processing_jobs)
      assert is_list(result.analysis_jobs)
    end

    test "returns tracks in position order", %{user: user} do
      playlist = playlist_fixture(%{user_id: user.id})
      t1 = track_fixture(%{user_id: user.id, title: "First", duration: 100})
      t2 = track_fixture(%{user_id: user.id, title: "Second", duration: 100})
      Music.add_track_to_playlist(playlist, t1, 0)
      Music.add_track_to_playlist(playlist, t2, 1)

      results = Music.list_playlist_tracks_with_status(playlist.id)
      assert [first, second] = results
      assert first.id == t1.id
      assert second.id == t2.id
    end
  end

  # ---------------------------------------------------------------------------
  # track_pipeline_complete?/1
  # ---------------------------------------------------------------------------

  describe "Music.track_pipeline_complete?/1" do
    test "returns false when no jobs exist", %{track: track} do
      refute Music.track_pipeline_complete?(track)
    end

    test "returns false when only download is complete", %{track: track} do
      download_job_fixture(%{track_id: track.id, status: :completed})
      refute Music.track_pipeline_complete?(track)
    end

    test "returns false when only analysis is complete", %{track: track} do
      analysis_job_fixture(%{track_id: track.id, status: :completed})
      refute Music.track_pipeline_complete?(track)
    end

    test "returns true when both download and analysis are complete", %{track: track} do
      download_job_fixture(%{track_id: track.id, status: :completed})
      analysis_job_fixture(%{track_id: track.id, status: :completed})
      assert Music.track_pipeline_complete?(track)
    end

    test "returns false when download completed but analysis is only queued", %{track: track} do
      download_job_fixture(%{track_id: track.id, status: :completed})
      analysis_job_fixture(%{track_id: track.id, status: :queued})
      refute Music.track_pipeline_complete?(track)
    end
  end

  # ---------------------------------------------------------------------------
  # PipelineBroadcaster.broadcast_playlist_track_update/3
  # ---------------------------------------------------------------------------

  describe "PipelineBroadcaster.broadcast_playlist_track_update/3" do
    test "no-op when playlist_id is nil", %{track: track} do
      # Should not raise and returns :ok
      assert :ok == PipelineBroadcaster.broadcast_playlist_track_update(nil, track.id, %{stage: :download, status: :completed, progress: 100})
    end

    test "broadcasts to playlist_pipeline topic", %{track: track} do
      playlist_id = Ecto.UUID.generate()
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "playlist_pipeline:#{playlist_id}")

      PipelineBroadcaster.broadcast_playlist_track_update(playlist_id, track.id, %{
        stage: :download,
        status: :completed,
        progress: 100
      })

      assert_receive {:playlist_track_update, payload}
      assert payload.track_id == track.id
      assert payload.playlist_id == playlist_id
      assert payload.stage == :download
      assert payload.status == :completed
      assert payload.progress == 100
    end

    test "merges update fields with track_id and playlist_id", %{track: track} do
      playlist_id = Ecto.UUID.generate()
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "playlist_pipeline:#{playlist_id}")

      PipelineBroadcaster.broadcast_playlist_track_update(playlist_id, track.id, %{
        stage: :processing,
        status: :processing,
        progress: 42
      })

      assert_receive {:playlist_track_update, payload}
      assert payload.stage == :processing
      assert payload.progress == 42
    end
  end
end
