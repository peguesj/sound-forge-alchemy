defmodule SoundForge.Music.ProcessingJobTest do
  use ExUnit.Case, async: true

  alias SoundForge.Music.ProcessingJob

  @valid_attrs %{
    track_id: Ecto.UUID.generate(),
    model: "htdemucs",
    status: :queued,
    progress: 0
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = ProcessingJob.changeset(%ProcessingJob{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires track_id" do
      changeset = ProcessingJob.changeset(%ProcessingJob{}, Map.delete(@valid_attrs, :track_id))
      refute changeset.valid?
    end

    test "validates status inclusion" do
      for status <- [:queued, :downloading, :processing, :completed, :failed] do
        changeset = ProcessingJob.changeset(%ProcessingJob{}, %{@valid_attrs | status: status})
        assert changeset.valid?, "Expected #{status} to be valid"
      end
    end

    test "validates progress range 0-100" do
      too_low = ProcessingJob.changeset(%ProcessingJob{}, %{@valid_attrs | progress: -1})
      refute too_low.valid?

      too_high = ProcessingJob.changeset(%ProcessingJob{}, %{@valid_attrs | progress: 101})
      refute too_high.valid?

      edges = ProcessingJob.changeset(%ProcessingJob{}, %{@valid_attrs | progress: 100})
      assert edges.valid?
    end

    test "accepts optional fields" do
      changeset =
        ProcessingJob.changeset(%ProcessingJob{}, %{
          @valid_attrs
          | model: "htdemucs_ft"
        })

      assert changeset.valid?
    end

    test "defaults model to htdemucs" do
      job = %ProcessingJob{}
      assert job.model == "htdemucs"
    end

    test "defaults engine to demucs" do
      job = %ProcessingJob{}
      assert job.engine == "demucs"
    end

    test "defaults preview to false" do
      job = %ProcessingJob{}
      assert job.preview == false
    end

    test "accepts engine and preview fields" do
      changeset =
        ProcessingJob.changeset(%ProcessingJob{}, Map.merge(@valid_attrs, %{engine: "lalalai", preview: true}))

      assert changeset.valid?
    end
  end
end
