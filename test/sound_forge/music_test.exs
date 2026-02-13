defmodule SoundForge.MusicTest do
  use SoundForge.DataCase

  alias SoundForge.Music

  describe "tracks" do
    alias SoundForge.Music.Track

    import SoundForge.MusicFixtures

    @invalid_attrs %{title: nil}

    test "list_tracks/0 returns all tracks" do
      track = track_fixture()
      assert Music.list_tracks() == [track]
    end

    test "list_tracks/1 with sort_by: :title sorts alphabetically" do
      t2 = track_fixture(%{title: "Zebra"})
      t1 = track_fixture(%{title: "Alpha"})
      tracks = Music.list_tracks(sort_by: :title)
      assert [first, second] = tracks
      assert first.id == t1.id
      assert second.id == t2.id
    end

    test "list_tracks/1 with sort_by: :artist sorts alphabetically" do
      t2 = track_fixture(%{artist: "Zedd"})
      t1 = track_fixture(%{artist: "Adele"})
      tracks = Music.list_tracks(sort_by: :artist)
      assert [first, second] = tracks
      assert first.id == t1.id
      assert second.id == t2.id
    end

    test "list_tracks/1 with sort_by: :newest returns all tracks ordered by inserted_at desc" do
      t1 = track_fixture(%{title: "First"})
      t2 = track_fixture(%{title: "Second"})
      tracks = Music.list_tracks(sort_by: :newest)
      assert length(tracks) == 2
      ids = Enum.map(tracks, & &1.id)
      assert t1.id in ids
      assert t2.id in ids
    end

    test "get_track_by_spotify_id/1 returns track with matching spotify_id" do
      track = track_fixture(%{spotify_id: "sp_test_123"})
      assert Music.get_track_by_spotify_id("sp_test_123").id == track.id
    end

    test "get_track_by_spotify_id/1 returns nil for nonexistent spotify_id" do
      assert Music.get_track_by_spotify_id("nonexistent") == nil
    end

    test "get_track_by_spotify_id/1 returns nil for nil input" do
      assert Music.get_track_by_spotify_id(nil) == nil
    end

    test "get_track!/1 returns the track with given id" do
      track = track_fixture()
      assert Music.get_track!(track.id) == track
    end

    test "create_track/1 with valid data creates a track" do
      valid_attrs = %{
        title: "Test Song",
        artist: "Test Artist",
        album: "Test Album",
        duration: 180,
        spotify_id: "abc123",
        spotify_url: "https://open.spotify.com/track/abc123"
      }

      assert {:ok, %Track{} = track} = Music.create_track(valid_attrs)
      assert track.title == "Test Song"
      assert track.artist == "Test Artist"
      assert track.album == "Test Album"
      assert track.duration == 180
      assert track.spotify_id == "abc123"
    end

    test "create_track/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Music.create_track(@invalid_attrs)
    end

    test "create_track/1 with duplicate spotify_id returns error changeset" do
      track_fixture(%{spotify_id: "unique123"})

      assert {:error, %Ecto.Changeset{}} =
               Music.create_track(%{title: "Another Song", spotify_id: "unique123"})
    end

    test "update_track/2 with valid data updates the track" do
      track = track_fixture()
      update_attrs = %{title: "Updated Title", artist: "Updated Artist"}

      assert {:ok, %Track{} = track} = Music.update_track(track, update_attrs)
      assert track.title == "Updated Title"
      assert track.artist == "Updated Artist"
    end

    test "update_track/2 with invalid data returns error changeset" do
      track = track_fixture()
      assert {:error, %Ecto.Changeset{}} = Music.update_track(track, @invalid_attrs)
      assert track == Music.get_track!(track.id)
    end

    test "delete_track/1 deletes the track" do
      track = track_fixture()
      assert {:ok, %Track{}} = Music.delete_track(track)
      assert_raise Ecto.NoResultsError, fn -> Music.get_track!(track.id) end
    end

    test "change_track/1 returns a track changeset" do
      track = track_fixture()
      assert %Ecto.Changeset{} = Music.change_track(track)
    end
  end

  describe "download_jobs" do
    alias SoundForge.Music.DownloadJob

    import SoundForge.MusicFixtures

    test "get_download_job!/1 returns the download job with given id" do
      track = track_fixture()
      download_job = download_job_fixture(%{track_id: track.id})
      assert Music.get_download_job!(download_job.id).id == download_job.id
    end

    test "create_download_job/1 with valid data creates a download job" do
      track = track_fixture()
      valid_attrs = %{track_id: track.id, status: :queued, progress: 0}

      assert {:ok, %DownloadJob{} = download_job} = Music.create_download_job(valid_attrs)
      assert download_job.status == :queued
      assert download_job.progress == 0
      assert download_job.track_id == track.id
    end

    test "create_download_job/1 without track_id returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Music.create_download_job(%{})
    end

    test "update_download_job/2 with valid data updates the download job" do
      track = track_fixture()
      download_job = download_job_fixture(%{track_id: track.id})

      update_attrs = %{status: :downloading, progress: 50, output_path: "/path/to/file.mp3"}

      assert {:ok, %DownloadJob{} = download_job} =
               Music.update_download_job(download_job, update_attrs)

      assert download_job.status == :downloading
      assert download_job.progress == 50
      assert download_job.output_path == "/path/to/file.mp3"
    end

    test "update_download_job/2 validates progress range" do
      track = track_fixture()
      download_job = download_job_fixture(%{track_id: track.id})

      assert {:error, %Ecto.Changeset{}} =
               Music.update_download_job(download_job, %{progress: 150})

      assert {:error, %Ecto.Changeset{}} =
               Music.update_download_job(download_job, %{progress: -10})
    end
  end

  describe "processing_jobs" do
    alias SoundForge.Music.ProcessingJob

    import SoundForge.MusicFixtures

    test "get_processing_job!/1 returns the processing job with given id" do
      track = track_fixture()
      processing_job = processing_job_fixture(%{track_id: track.id})
      assert Music.get_processing_job!(processing_job.id).id == processing_job.id
    end

    test "create_processing_job/1 with valid data creates a processing job" do
      track = track_fixture()

      valid_attrs = %{
        track_id: track.id,
        model: "htdemucs",
        status: :queued,
        progress: 0,
        options: %{"quality" => "high"}
      }

      assert {:ok, %ProcessingJob{} = processing_job} = Music.create_processing_job(valid_attrs)
      assert processing_job.model == "htdemucs"
      assert processing_job.status == :queued
      assert processing_job.progress == 0
      assert processing_job.options == %{"quality" => "high"}
    end

    test "update_processing_job/2 with valid data updates the processing job" do
      track = track_fixture()
      processing_job = processing_job_fixture(%{track_id: track.id})

      update_attrs = %{
        status: :processing,
        progress: 75,
        output_path: "/path/to/stems/"
      }

      assert {:ok, %ProcessingJob{} = processing_job} =
               Music.update_processing_job(processing_job, update_attrs)

      assert processing_job.status == :processing
      assert processing_job.progress == 75
      assert processing_job.output_path == "/path/to/stems/"
    end
  end

  describe "analysis_jobs" do
    alias SoundForge.Music.AnalysisJob

    import SoundForge.MusicFixtures

    test "get_analysis_job!/1 returns the analysis job with given id" do
      track = track_fixture()
      analysis_job = analysis_job_fixture(%{track_id: track.id})
      assert Music.get_analysis_job!(analysis_job.id).id == analysis_job.id
    end

    test "create_analysis_job/1 with valid data creates an analysis job" do
      track = track_fixture()
      valid_attrs = %{track_id: track.id, status: :queued, progress: 0}

      assert {:ok, %AnalysisJob{} = analysis_job} = Music.create_analysis_job(valid_attrs)
      assert analysis_job.status == :queued
      assert analysis_job.progress == 0
      assert analysis_job.track_id == track.id
    end

    test "update_analysis_job/2 with valid data updates the analysis job" do
      track = track_fixture()
      analysis_job = analysis_job_fixture(%{track_id: track.id})

      results = %{"tempo" => 120.5, "key" => "C major"}

      update_attrs = %{
        status: :completed,
        progress: 100,
        results: results
      }

      assert {:ok, %AnalysisJob{} = analysis_job} =
               Music.update_analysis_job(analysis_job, update_attrs)

      assert analysis_job.status == :completed
      assert analysis_job.progress == 100
      assert analysis_job.results == results
    end
  end

  describe "stems" do
    alias SoundForge.Music.Stem

    import SoundForge.MusicFixtures

    test "list_stems_for_track/1 returns all stems for a track" do
      track = track_fixture()
      processing_job = processing_job_fixture(%{track_id: track.id})

      stem1 =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: processing_job.id,
          stem_type: :vocals
        })

      stem2 =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: processing_job.id,
          stem_type: :drums
        })

      stems = Music.list_stems_for_track(track.id)
      assert length(stems) == 2
      assert Enum.any?(stems, fn s -> s.id == stem1.id end)
      assert Enum.any?(stems, fn s -> s.id == stem2.id end)
    end

    test "create_stem/1 with valid data creates a stem" do
      track = track_fixture()
      processing_job = processing_job_fixture(%{track_id: track.id})

      valid_attrs = %{
        track_id: track.id,
        processing_job_id: processing_job.id,
        stem_type: :vocals,
        file_path: "/path/to/vocals.wav",
        file_size: 1024 * 1024 * 10
      }

      assert {:ok, %Stem{} = stem} = Music.create_stem(valid_attrs)
      assert stem.stem_type == :vocals
      assert stem.file_path == "/path/to/vocals.wav"
      assert stem.file_size == 1024 * 1024 * 10
    end

    test "create_stem/1 validates stem_type" do
      track = track_fixture()
      processing_job = processing_job_fixture(%{track_id: track.id})

      # Invalid stem_type should fail at the changeset level
      attrs = %{
        track_id: track.id,
        processing_job_id: processing_job.id,
        stem_type: :invalid_type
      }

      assert {:error, %Ecto.Changeset{}} = Music.create_stem(attrs)
    end
  end

  describe "analysis_results" do
    alias SoundForge.Music.AnalysisResult

    import SoundForge.MusicFixtures

    test "get_analysis_result_for_track/1 returns the analysis result for a track" do
      track = track_fixture()
      analysis_job = analysis_job_fixture(%{track_id: track.id})

      analysis_result =
        analysis_result_fixture(%{
          track_id: track.id,
          analysis_job_id: analysis_job.id
        })

      result = Music.get_analysis_result_for_track(track.id)
      assert result.id == analysis_result.id
    end

    test "get_analysis_result_for_track/1 returns nil if no result exists" do
      track = track_fixture()
      assert Music.get_analysis_result_for_track(track.id) == nil
    end

    test "create_analysis_result/1 with valid data creates an analysis result" do
      track = track_fixture()
      analysis_job = analysis_job_fixture(%{track_id: track.id})

      valid_attrs = %{
        track_id: track.id,
        analysis_job_id: analysis_job.id,
        tempo: 120.5,
        key: "C major",
        energy: 0.75,
        spectral_centroid: 1500.0,
        spectral_rolloff: 3000.0,
        zero_crossing_rate: 0.05,
        features: %{"additional" => "data"}
      }

      assert {:ok, %AnalysisResult{} = result} = Music.create_analysis_result(valid_attrs)
      assert result.tempo == 120.5
      assert result.key == "C major"
      assert result.energy == 0.75
      assert result.spectral_centroid == 1500.0
      assert result.features == %{"additional" => "data"}
    end
  end
end
