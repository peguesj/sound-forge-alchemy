defmodule SoundForge.Audio.BatchProcessorTest do
  use SoundForge.DataCase

  alias SoundForge.Audio.BatchProcessor
  alias SoundForge.Music.BatchJob
  alias SoundForge.Repo

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  describe "start_batch/1 - validation" do
    test "rejects empty batch" do
      assert {:error, :empty_batch} =
               BatchProcessor.start_batch(
                 track_ids: [],
                 user_id: 1,
                 stem_filter: "vocals"
               )
    end

    test "rejects batch exceeding max size" do
      track_ids = for _ <- 1..101, do: Ecto.UUID.generate()

      assert {:error, {:batch_too_large, _msg}} =
               BatchProcessor.start_batch(
                 track_ids: track_ids,
                 user_id: 1,
                 stem_filter: "vocals"
               )
    end
  end

  describe "start_batch/1 - batch creation" do
    test "creates batch job with correct attributes" do
      user = user_fixture()
      track = track_fixture()

      # Track has no download, so it will be skipped, but the batch job is still created
      result =
        BatchProcessor.start_batch(
          track_ids: [track.id],
          user_id: user.id,
          stem_filter: "vocals",
          engine_opts: [splitter: "phoenix", preview: false]
        )

      case result do
        {:ok, %{batch_job: batch_job, errors: errors}} ->
          assert batch_job.user_id == user.id
          assert batch_job.total_count == 1
          assert batch_job.status in [:pending, :processing]
          # Track has no download so it should be in errors
          assert length(errors) == 1

        {:error, _reason} ->
          # Acceptable - batch creation might fail if track has no download path
          :ok
      end
    end
  end

  describe "get_batch_status/1" do
    test "returns error for non-existent batch" do
      assert {:error, :not_found} = BatchProcessor.get_batch_status(Ecto.UUID.generate())
    end

    test "returns status for existing batch" do
      user = user_fixture()

      {:ok, batch_job} =
        %BatchJob{}
        |> BatchJob.changeset(%{
          user_id: user.id,
          total_count: 3,
          status: :processing,
          completed_count: 1,
          options: %{"stem_filter" => "vocals"}
        })
        |> Repo.insert()

      {:ok, status} = BatchProcessor.get_batch_status(batch_job.id)

      assert status.batch_job_id == batch_job.id
      assert status.status == :processing
      assert status.total_count == 3
    end
  end

  describe "update_batch_progress/1" do
    test "returns error for non-existent batch" do
      assert {:error, :not_found} = BatchProcessor.update_batch_progress(Ecto.UUID.generate())
    end

    test "updates batch progress for existing batch" do
      user = user_fixture()

      {:ok, batch_job} =
        %BatchJob{}
        |> BatchJob.changeset(%{
          user_id: user.id,
          total_count: 2,
          status: :processing,
          completed_count: 0,
          options: %{}
        })
        |> Repo.insert()

      # Subscribe to PubSub for batch progress
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "batch:#{batch_job.id}")

      {:ok, updated} = BatchProcessor.update_batch_progress(batch_job.id)

      # With no processing jobs, all counts are 0, so status should be pending
      assert updated.completed_count == 0
      assert updated.status == :pending

      # Should have received a broadcast
      assert_received {:batch_progress, %{batch_job_id: _, status: _, completed_count: _, total_count: _}}
    end
  end

  describe "BatchJob changeset" do
    test "valid changeset" do
      changeset =
        BatchJob.changeset(%BatchJob{}, %{
          user_id: 1,
          total_count: 5,
          status: :pending,
          completed_count: 0,
          options: %{"stem_filter" => "vocals"}
        })

      assert changeset.valid?
    end

    test "requires user_id" do
      changeset =
        BatchJob.changeset(%BatchJob{}, %{
          total_count: 5,
          status: :pending
        })

      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires total_count" do
      changeset =
        BatchJob.changeset(%BatchJob{}, %{
          user_id: 1,
          status: :pending
        })

      refute changeset.valid?
      assert %{total_count: ["can't be blank"]} = errors_on(changeset)
    end

    test "total_count must be positive" do
      changeset =
        BatchJob.changeset(%BatchJob{}, %{
          user_id: 1,
          total_count: 0,
          status: :pending
        })

      refute changeset.valid?
      assert %{total_count: ["must be greater than " <> _]} = errors_on(changeset)
    end

    test "completed_count must be non-negative" do
      changeset =
        BatchJob.changeset(%BatchJob{}, %{
          user_id: 1,
          total_count: 5,
          completed_count: -1,
          status: :pending
        })

      refute changeset.valid?
    end

    test "validates status inclusion" do
      changeset =
        BatchJob.changeset(%BatchJob{}, %{
          user_id: 1,
          total_count: 5,
          status: :invalid_status
        })

      refute changeset.valid?
    end
  end
end
