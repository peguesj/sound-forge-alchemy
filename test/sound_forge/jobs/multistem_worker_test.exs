defmodule SoundForge.Jobs.MultiStemWorkerTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.MultiStemWorker

  describe "worker configuration" do
    test "uses processing queue" do
      changeset = MultiStemWorker.new(%{"track_id" => "test"})
      assert changeset.changes.queue == "processing"
    end

    test "has max_attempts of 3" do
      changeset = MultiStemWorker.new(%{"track_id" => "test"})
      assert changeset.changes.max_attempts == 3
    end

    test "has priority 2" do
      changeset = MultiStemWorker.new(%{"track_id" => "test"})
      assert changeset.changes.priority == 2
    end
  end

  describe "new/1" do
    test "creates valid job with required args" do
      args = %{
        "track_id" => Ecto.UUID.generate(),
        "job_id" => Ecto.UUID.generate(),
        "file_path" => "priv/uploads/downloads/test.mp3",
        "stem_list" => ["vocals", "drum", "bass"]
      }

      changeset = MultiStemWorker.new(args)
      assert changeset.valid?
    end

    test "creates job with optional extraction_level and splitter" do
      args = %{
        "track_id" => Ecto.UUID.generate(),
        "job_id" => Ecto.UUID.generate(),
        "file_path" => "priv/uploads/downloads/test.mp3",
        "stem_list" => ["vocals", "drum"],
        "extraction_level" => "high",
        "splitter" => "orion"
      }

      changeset = MultiStemWorker.new(args)
      assert changeset.valid?
    end
  end
end
