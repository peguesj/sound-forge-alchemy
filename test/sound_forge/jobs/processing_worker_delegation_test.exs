defmodule SoundForge.Jobs.ProcessingWorkerDelegationTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.ProcessingWorker

  describe "perform/1 - lalal.ai delegation" do
    test "delegates voice_clean mode to VoiceCleanWorker" do
      job = %Oban.Job{
        args: %{
          "engine" => "lalalai",
          "mode" => "voice_clean",
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "/tmp/test.mp3"
        }
      }

      assert {:discard, :delegated_to_voice_clean} = ProcessingWorker.perform(job)
    end

    test "delegates demuser mode to DemuserWorker" do
      job = %Oban.Job{
        args: %{
          "engine" => "lalalai",
          "mode" => "demuser",
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "/tmp/test.mp3"
        }
      }

      assert {:discard, :delegated_to_demuser} = ProcessingWorker.perform(job)
    end

    test "delegates multistem mode to MultiStemWorker" do
      job = %Oban.Job{
        args: %{
          "engine" => "lalalai",
          "mode" => "multistem",
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "/tmp/test.mp3"
        }
      }

      assert {:discard, :delegated_to_multistem} = ProcessingWorker.perform(job)
    end

    test "delegates voice_change mode to VoiceChangeWorker" do
      job = %Oban.Job{
        args: %{
          "engine" => "lalalai",
          "mode" => "voice_change",
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "/tmp/test.mp3"
        }
      }

      assert {:discard, :delegated_to_voice_change} = ProcessingWorker.perform(job)
    end

    test "delegates generic lalalai engine to LalalAIWorker" do
      job = %Oban.Job{
        args: %{
          "engine" => "lalalai",
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "/tmp/test.mp3"
        }
      }

      assert {:discard, :delegated_to_lalalai} = ProcessingWorker.perform(job)
    end
  end

  describe "worker configuration" do
    test "uses processing queue" do
      changeset = ProcessingWorker.new(%{"track_id" => "test"})
      assert changeset.changes.queue == "processing"
    end

    test "has max_attempts of 2" do
      changeset = ProcessingWorker.new(%{"track_id" => "test"})
      assert changeset.changes.max_attempts == 2
    end

    test "has priority 2" do
      changeset = ProcessingWorker.new(%{"track_id" => "test"})
      assert changeset.changes.priority == 2
    end
  end
end
