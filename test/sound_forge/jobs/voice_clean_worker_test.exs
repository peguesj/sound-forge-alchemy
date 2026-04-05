defmodule SoundForge.Jobs.VoiceCleanWorkerTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.VoiceCleanWorker

  describe "worker configuration" do
    test "uses processing queue" do
      changeset = VoiceCleanWorker.new(%{"track_id" => "test"})
      assert changeset.changes.queue == "processing"
    end

    test "has max_attempts of 3" do
      changeset = VoiceCleanWorker.new(%{"track_id" => "test"})
      assert changeset.changes.max_attempts == 3
    end

    test "has priority 2" do
      changeset = VoiceCleanWorker.new(%{"track_id" => "test"})
      assert changeset.changes.priority == 2
    end
  end

  describe "new/1" do
    test "creates valid job with required args" do
      args = %{
        "track_id" => Ecto.UUID.generate(),
        "job_id" => Ecto.UUID.generate(),
        "file_path" => "priv/uploads/downloads/test.mp3"
      }

      changeset = VoiceCleanWorker.new(args)
      assert changeset.valid?
    end

    test "creates job with optional noise_cancelling and dereverb args" do
      args = %{
        "track_id" => Ecto.UUID.generate(),
        "job_id" => Ecto.UUID.generate(),
        "file_path" => "priv/uploads/downloads/test.mp3",
        "noise_cancelling_level" => 2,
        "splitter" => "phoenix",
        "dereverb" => true,
        "encoder_format" => "wav"
      }

      changeset = VoiceCleanWorker.new(args)
      assert changeset.valid?
    end
  end
end
