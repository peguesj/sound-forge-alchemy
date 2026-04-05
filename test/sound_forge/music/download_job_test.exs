defmodule SoundForge.Music.DownloadJobTest do
  use ExUnit.Case, async: true

  alias SoundForge.Music.DownloadJob

  @valid_attrs %{
    track_id: Ecto.UUID.generate(),
    status: :queued,
    progress: 0
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = DownloadJob.changeset(%DownloadJob{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires track_id" do
      changeset = DownloadJob.changeset(%DownloadJob{}, Map.delete(@valid_attrs, :track_id))
      refute changeset.valid?
    end

    test "validates progress range 0-100" do
      too_low = DownloadJob.changeset(%DownloadJob{}, %{@valid_attrs | progress: -1})
      refute too_low.valid?

      too_high = DownloadJob.changeset(%DownloadJob{}, %{@valid_attrs | progress: 101})
      refute too_high.valid?

      valid = DownloadJob.changeset(%DownloadJob{}, %{@valid_attrs | progress: 50})
      assert valid.valid?
    end

    test "validates status inclusion" do
      for status <- [:queued, :downloading, :processing, :completed, :failed] do
        changeset = DownloadJob.changeset(%DownloadJob{}, %{@valid_attrs | status: status})
        assert changeset.valid?, "Expected #{status} to be valid"
      end
    end

    test "accepts optional output_path and file_size" do
      changeset =
        DownloadJob.changeset(%DownloadJob{}, Map.merge(@valid_attrs, %{
          output_path: "priv/uploads/downloads/song.mp3",
          file_size: 5_242_880
        }))

      assert changeset.valid?
    end

    test "defaults status to queued" do
      job = %DownloadJob{}
      assert job.status == :queued
    end

    test "defaults progress to 0" do
      job = %DownloadJob{}
      assert job.progress == 0
    end
  end
end
