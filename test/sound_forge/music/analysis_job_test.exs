defmodule SoundForge.Music.AnalysisJobTest do
  use ExUnit.Case, async: true

  alias SoundForge.Music.AnalysisJob

  @valid_attrs %{
    track_id: Ecto.UUID.generate(),
    status: :queued,
    progress: 0
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = AnalysisJob.changeset(%AnalysisJob{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires track_id" do
      changeset = AnalysisJob.changeset(%AnalysisJob{}, Map.delete(@valid_attrs, :track_id))
      refute changeset.valid?
    end

    test "validates status inclusion" do
      for status <- [:queued, :downloading, :processing, :completed, :failed] do
        changeset = AnalysisJob.changeset(%AnalysisJob{}, %{@valid_attrs | status: status})
        assert changeset.valid?, "Expected #{status} to be valid"
      end
    end

    test "validates progress range 0-100" do
      too_low = AnalysisJob.changeset(%AnalysisJob{}, %{@valid_attrs | progress: -1})
      refute too_low.valid?

      too_high = AnalysisJob.changeset(%AnalysisJob{}, %{@valid_attrs | progress: 101})
      refute too_high.valid?
    end

    test "accepts results map" do
      changeset =
        AnalysisJob.changeset(
          %AnalysisJob{},
          Map.put(@valid_attrs, :results, %{"tempo" => 128.0})
        )

      assert changeset.valid?
    end

    test "accepts error string" do
      changeset =
        AnalysisJob.changeset(%AnalysisJob{}, Map.put(@valid_attrs, :error, "Analyzer crashed"))

      assert changeset.valid?
    end

    test "defaults status to queued" do
      job = %AnalysisJob{}
      assert job.status == :queued
    end

    test "defaults progress to 0" do
      job = %AnalysisJob{}
      assert job.progress == 0
    end
  end
end
