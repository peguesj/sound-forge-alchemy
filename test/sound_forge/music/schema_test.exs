defmodule SoundForge.Music.SchemaTest do
  use SoundForge.DataCase

  alias SoundForge.Music.{AnalysisJob, AnalysisResult, DownloadJob, ProcessingJob, Stem, Track}

  describe "Track changeset" do
    test "valid attributes" do
      changeset = Track.changeset(%Track{}, %{title: "My Song", artist: "Artist"})
      assert changeset.valid?
    end

    test "requires title" do
      changeset = Track.changeset(%Track{}, %{artist: "Artist"})
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:title]
    end

    test "validates title length" do
      long_title = String.duplicate("a", 501)
      changeset = Track.changeset(%Track{}, %{title: long_title})
      refute changeset.valid?
      assert {"should be at most %{count} character(s)", _} = changeset.errors[:title]
    end

    test "validates duration is positive" do
      changeset = Track.changeset(%Track{}, %{title: "Song", duration: -5})
      refute changeset.valid?
      assert {"must be greater than %{number}", _} = changeset.errors[:duration]
    end

    test "allows nil duration" do
      changeset = Track.changeset(%Track{}, %{title: "Song", duration: nil})
      assert changeset.valid?
    end

    test "enforces unique spotify_id" do
      {:ok, _} =
        SoundForge.Repo.insert(
          Track.changeset(%Track{}, %{title: "Song 1", spotify_id: "abc123"})
        )

      {:error, changeset} =
        SoundForge.Repo.insert(
          Track.changeset(%Track{}, %{title: "Song 2", spotify_id: "abc123"})
        )

      assert {"has already been taken", _} = changeset.errors[:spotify_id]
    end
  end

  describe "Stem changeset" do
    test "valid attributes" do
      changeset =
        Stem.changeset(%Stem{}, %{
          processing_job_id: Ecto.UUID.generate(),
          track_id: Ecto.UUID.generate(),
          stem_type: :vocals,
          file_path: "/path/to/file.wav"
        })

      assert changeset.valid?
    end

    test "requires processing_job_id, track_id, and stem_type" do
      changeset = Stem.changeset(%Stem{}, %{})
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:processing_job_id]
      assert {"can't be blank", _} = changeset.errors[:track_id]
      assert {"can't be blank", _} = changeset.errors[:stem_type]
    end

    test "validates stem_type inclusion" do
      changeset =
        Stem.changeset(%Stem{}, %{
          processing_job_id: Ecto.UUID.generate(),
          track_id: Ecto.UUID.generate(),
          stem_type: :invalid_type
        })

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:stem_type]
    end

    test "accepts all valid stem types" do
      for type <- [:vocals, :drums, :bass, :other, :guitar, :piano] do
        changeset =
          Stem.changeset(%Stem{}, %{
            processing_job_id: Ecto.UUID.generate(),
            track_id: Ecto.UUID.generate(),
            stem_type: type
          })

        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end
  end

  describe "DownloadJob changeset" do
    test "valid attributes" do
      changeset =
        DownloadJob.changeset(%DownloadJob{}, %{
          track_id: Ecto.UUID.generate(),
          status: :queued
        })

      assert changeset.valid?
    end

    test "requires track_id" do
      changeset = DownloadJob.changeset(%DownloadJob{}, %{})
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:track_id]
    end

    test "defaults status to queued" do
      changeset = DownloadJob.changeset(%DownloadJob{}, %{track_id: Ecto.UUID.generate()})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == :queued
    end

    test "validates progress range 0-100" do
      changeset =
        DownloadJob.changeset(%DownloadJob{}, %{
          track_id: Ecto.UUID.generate(),
          progress: 101
        })

      refute changeset.valid?
      assert {"must be less than or equal to %{number}", _} = changeset.errors[:progress]
    end

    test "rejects negative progress" do
      changeset =
        DownloadJob.changeset(%DownloadJob{}, %{
          track_id: Ecto.UUID.generate(),
          progress: -1
        })

      refute changeset.valid?
      assert {"must be greater than or equal to %{number}", _} = changeset.errors[:progress]
    end
  end

  describe "ProcessingJob changeset" do
    test "valid attributes" do
      changeset =
        ProcessingJob.changeset(%ProcessingJob{}, %{
          track_id: Ecto.UUID.generate(),
          status: :queued,
          model: "htdemucs"
        })

      assert changeset.valid?
    end

    test "requires track_id" do
      changeset = ProcessingJob.changeset(%ProcessingJob{}, %{})
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:track_id]
    end

    test "defaults status to queued" do
      changeset = ProcessingJob.changeset(%ProcessingJob{}, %{track_id: Ecto.UUID.generate()})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == :queued
    end
  end

  describe "AnalysisJob changeset" do
    test "valid attributes" do
      changeset =
        AnalysisJob.changeset(%AnalysisJob{}, %{
          track_id: Ecto.UUID.generate(),
          status: :queued
        })

      assert changeset.valid?
    end

    test "requires track_id" do
      changeset = AnalysisJob.changeset(%AnalysisJob{}, %{})
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:track_id]
    end

    test "defaults status to queued" do
      changeset = AnalysisJob.changeset(%AnalysisJob{}, %{track_id: Ecto.UUID.generate()})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == :queued
    end
  end

  describe "AnalysisResult changeset" do
    test "valid attributes" do
      changeset =
        AnalysisResult.changeset(%AnalysisResult{}, %{
          track_id: Ecto.UUID.generate(),
          analysis_job_id: Ecto.UUID.generate(),
          tempo: 120.5,
          key: "C major",
          energy: 0.85
        })

      assert changeset.valid?
    end

    test "requires track_id and analysis_job_id" do
      changeset = AnalysisResult.changeset(%AnalysisResult{}, %{})
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:track_id]
      assert {"can't be blank", _} = changeset.errors[:analysis_job_id]
    end

    test "accepts spectral features" do
      changeset =
        AnalysisResult.changeset(%AnalysisResult{}, %{
          track_id: Ecto.UUID.generate(),
          analysis_job_id: Ecto.UUID.generate(),
          spectral_centroid: 1500.0,
          spectral_rolloff: 3000.0,
          zero_crossing_rate: 0.05
        })

      assert changeset.valid?
    end

    test "accepts features map" do
      changeset =
        AnalysisResult.changeset(%AnalysisResult{}, %{
          track_id: Ecto.UUID.generate(),
          analysis_job_id: Ecto.UUID.generate(),
          features: %{"chroma" => [0.1, 0.2, 0.3], "mfcc" => [1.0, 2.0]}
        })

      assert changeset.valid?

      assert Ecto.Changeset.get_field(changeset, :features) == %{
               "chroma" => [0.1, 0.2, 0.3],
               "mfcc" => [1.0, 2.0]
             }
    end
  end
end
