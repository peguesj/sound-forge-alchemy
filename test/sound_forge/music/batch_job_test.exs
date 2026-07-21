defmodule SoundForge.Music.BatchJobTest do
  use ExUnit.Case, async: true

  alias SoundForge.Music.BatchJob

  @valid_attrs %{
    user_id: 1,
    total_count: 5,
    status: :pending,
    completed_count: 0
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = BatchJob.changeset(%BatchJob{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires user_id" do
      changeset = BatchJob.changeset(%BatchJob{}, Map.delete(@valid_attrs, :user_id))
      refute changeset.valid?
    end

    test "requires total_count" do
      changeset = BatchJob.changeset(%BatchJob{}, Map.delete(@valid_attrs, :total_count))
      refute changeset.valid?
    end

    test "validates total_count > 0" do
      changeset = BatchJob.changeset(%BatchJob{}, %{@valid_attrs | total_count: 0})
      refute changeset.valid?
    end

    test "validates completed_count >= 0" do
      changeset = BatchJob.changeset(%BatchJob{}, %{@valid_attrs | completed_count: -1})
      refute changeset.valid?
    end

    test "validates status inclusion" do
      for status <- [:pending, :processing, :completed, :failed] do
        changeset = BatchJob.changeset(%BatchJob{}, %{@valid_attrs | status: status})
        assert changeset.valid?, "Expected #{status} to be valid"
      end
    end

    test "accepts optional options map" do
      changeset =
        BatchJob.changeset(%BatchJob{}, Map.put(@valid_attrs, :options, %{"model" => "htdemucs"}))

      assert changeset.valid?
    end

    test "defaults status to pending" do
      job = %BatchJob{}
      assert job.status == :pending
    end

    test "defaults completed_count to 0" do
      job = %BatchJob{}
      assert job.completed_count == 0
    end
  end
end
