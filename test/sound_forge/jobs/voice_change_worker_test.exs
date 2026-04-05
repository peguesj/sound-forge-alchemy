defmodule SoundForge.Jobs.VoiceChangeWorkerTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.VoiceChangeWorker

  describe "worker configuration" do
    test "uses processing queue" do
      changeset = VoiceChangeWorker.new(%{"track_id" => "test"})
      assert changeset.changes.queue == "processing"
    end

    test "has max_attempts of 3" do
      changeset = VoiceChangeWorker.new(%{"track_id" => "test"})
      assert changeset.changes.max_attempts == 3
    end

    test "has priority 2" do
      changeset = VoiceChangeWorker.new(%{"track_id" => "test"})
      assert changeset.changes.priority == 2
    end
  end

  describe "new/1" do
    test "creates valid job with required args" do
      args = %{
        "track_id" => Ecto.UUID.generate(),
        "job_id" => Ecto.UUID.generate(),
        "file_path" => "priv/uploads/downloads/test.mp3",
        "voice_pack_id" => "builtin_male_1"
      }

      changeset = VoiceChangeWorker.new(args)
      assert changeset.valid?
    end

    test "creates job with all optional args" do
      args = %{
        "track_id" => Ecto.UUID.generate(),
        "job_id" => Ecto.UUID.generate(),
        "file_path" => "priv/uploads/downloads/test.mp3",
        "voice_pack_id" => Ecto.UUID.generate(),
        "accent" => 0.8,
        "tonality_reference" => "voice_pack",
        "dereverb" => true,
        "encoder_format" => "mp3"
      }

      changeset = VoiceChangeWorker.new(args)
      assert changeset.valid?
    end
  end
end
