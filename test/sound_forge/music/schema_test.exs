defmodule SoundForge.Music.SchemaTest do
  use SoundForge.DataCase

  alias SoundForge.Music.{Track, Stem, DownloadJob, ProcessingJob, AnalysisJob}

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
      {:ok, _} = SoundForge.Repo.insert(Track.changeset(%Track{}, %{title: "Song 1", spotify_id: "abc123"}))

      {:error, changeset} =
        SoundForge.Repo.insert(Track.changeset(%Track{}, %{title: "Song 2", spotify_id: "abc123"}))

      assert {"has already been taken", _} = changeset.errors[:spotify_id]
    end
  end

  describe "Stem changeset" do
    test "valid attributes" do
      changeset = Stem.changeset(%Stem{}, %{
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
      changeset = Stem.changeset(%Stem{}, %{
        processing_job_id: Ecto.UUID.generate(),
        track_id: Ecto.UUID.generate(),
        stem_type: :invalid_type
      })
      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:stem_type]
    end

    test "accepts all valid stem types" do
      for type <- [:vocals, :drums, :bass, :other, :guitar, :piano] do
        changeset = Stem.changeset(%Stem{}, %{
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
      changeset = DownloadJob.changeset(%DownloadJob{}, %{
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
  end

  describe "ProcessingJob changeset" do
    test "valid attributes" do
      changeset = ProcessingJob.changeset(%ProcessingJob{}, %{
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
      changeset = AnalysisJob.changeset(%AnalysisJob{}, %{
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
end
