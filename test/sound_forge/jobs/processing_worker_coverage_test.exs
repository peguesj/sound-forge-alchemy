defmodule SoundForge.Jobs.ProcessingWorkerCoverageTest do
  @moduledoc "Tests for ProcessingWorker delegation routing."
  use SoundForge.DataCase

  alias SoundForge.Jobs.ProcessingWorker

  describe "perform/1 delegation routing" do
    test "lalalai voice_clean mode delegates" do
      args = %{"engine" => "lalalai", "mode" => "voice_clean", "track_id" => "123"}
      job = %Oban.Job{args: args, id: 1, worker: "SoundForge.Jobs.ProcessingWorker"}
      assert {:discard, :delegated_to_voice_clean} = ProcessingWorker.perform(job)
    end

    test "lalalai demuser mode delegates" do
      args = %{"engine" => "lalalai", "mode" => "demuser", "track_id" => "123"}
      job = %Oban.Job{args: args, id: 2, worker: "SoundForge.Jobs.ProcessingWorker"}
      assert {:discard, :delegated_to_demuser} = ProcessingWorker.perform(job)
    end

    test "lalalai multistem mode delegates" do
      args = %{"engine" => "lalalai", "mode" => "multistem", "track_id" => "123"}
      job = %Oban.Job{args: args, id: 3, worker: "SoundForge.Jobs.ProcessingWorker"}
      assert {:discard, :delegated_to_multistem} = ProcessingWorker.perform(job)
    end

    test "lalalai voice_change mode delegates" do
      args = %{"engine" => "lalalai", "mode" => "voice_change", "track_id" => "123"}
      job = %Oban.Job{args: args, id: 4, worker: "SoundForge.Jobs.ProcessingWorker"}
      assert {:discard, :delegated_to_voice_change} = ProcessingWorker.perform(job)
    end

    test "lalalai default mode delegates to lalalai worker" do
      args = %{"engine" => "lalalai", "track_id" => "123"}
      job = %Oban.Job{args: args, id: 5, worker: "SoundForge.Jobs.ProcessingWorker"}
      assert {:discard, :delegated_to_lalalai} = ProcessingWorker.perform(job)
    end
  end

  describe "new/1" do
    test "creates a valid changeset" do
      args = %{
        "track_id" => "abc",
        "job_id" => "xyz",
        "file_path" => "/tmp/test.mp3",
        "model" => "htdemucs"
      }

      changeset = ProcessingWorker.new(args)
      assert changeset.valid?
    end
  end
end
