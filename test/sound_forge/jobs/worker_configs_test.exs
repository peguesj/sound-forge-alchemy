defmodule SoundForge.Jobs.WorkerConfigsTest do
  @moduledoc """
  Tests Oban worker configurations for all workers that depend on external
  services (lalal.ai, Demucs, Python, etc.) and can't have their perform/1
  tested without those services.
  """
  use ExUnit.Case, async: true

  describe "DemuserWorker" do
    test "uses processing queue" do
      changeset = SoundForge.Jobs.DemuserWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.queue == "processing"
    end

    test "has max_attempts of 3" do
      changeset = SoundForge.Jobs.DemuserWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.max_attempts == 3
    end

    test "creates valid changeset" do
      changeset =
        SoundForge.Jobs.DemuserWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "/tmp/test.mp3"
        })

      assert changeset.valid?
    end
  end

  describe "MultiStemWorker" do
    test "uses processing queue" do
      changeset = SoundForge.Jobs.MultiStemWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.queue == "processing"
    end

    test "has max_attempts of 3" do
      changeset = SoundForge.Jobs.MultiStemWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.max_attempts == 3
    end

    test "creates valid changeset with stem_list" do
      changeset =
        SoundForge.Jobs.MultiStemWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "/tmp/test.mp3",
          "stem_list" => ["vocals", "drum", "bass"]
        })

      assert changeset.valid?
    end
  end

  describe "VoiceChangeWorker" do
    test "uses processing queue" do
      changeset = SoundForge.Jobs.VoiceChangeWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.queue == "processing"
    end

    test "has max_attempts of 3" do
      changeset = SoundForge.Jobs.VoiceChangeWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.max_attempts == 3
    end

    test "creates valid changeset with voice pack args" do
      changeset =
        SoundForge.Jobs.VoiceChangeWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "/tmp/test.mp3",
          "voice_pack_id" => "test_pack",
          "accent" => 0.5
        })

      assert changeset.valid?
    end
  end

  describe "VoiceCleanWorker" do
    test "uses processing queue" do
      changeset = SoundForge.Jobs.VoiceCleanWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.queue == "processing"
    end

    test "has max_attempts of 3" do
      changeset = SoundForge.Jobs.VoiceCleanWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.max_attempts == 3
    end

    test "creates valid changeset with noise cancelling args" do
      changeset =
        SoundForge.Jobs.VoiceCleanWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "/tmp/test.mp3",
          "noise_cancelling_level" => 1
        })

      assert changeset.valid?
    end
  end

  describe "ChefWorker" do
    test "uses processing queue" do
      changeset = SoundForge.Jobs.ChefWorker.new(%{"user_id" => 1})
      assert changeset.changes.queue == "processing"
    end

    test "has max_attempts of 3" do
      changeset = SoundForge.Jobs.ChefWorker.new(%{"user_id" => 1})
      assert changeset.changes.max_attempts == 3
    end

    test "has priority 3" do
      changeset = SoundForge.Jobs.ChefWorker.new(%{"user_id" => 1})
      assert changeset.changes.priority == 3
    end

    test "creates valid changeset with recipe args" do
      changeset =
        SoundForge.Jobs.ChefWorker.new(%{
          "user_id" => 1,
          "track_ids" => [Ecto.UUID.generate()],
          "stem_types" => ["vocals", "drums"],
          "cue_plan" => [],
          "candidate_track_ids" => [],
          "recipe_meta" => %{}
        })

      assert changeset.valid?
    end
  end

  describe "AutoCueWorker" do
    test "uses analysis queue" do
      changeset = SoundForge.Jobs.AutoCueWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.queue == "analysis"
    end

    test "has priority 3" do
      changeset = SoundForge.Jobs.AutoCueWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.priority == 3
    end
  end

  describe "AnalysisWorker" do
    test "uses analysis queue" do
      changeset = SoundForge.Jobs.AnalysisWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.queue == "analysis"
    end

    test "has max_attempts of 2" do
      changeset = SoundForge.Jobs.AnalysisWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.max_attempts == 2
    end

    test "has priority 2" do
      changeset = SoundForge.Jobs.AnalysisWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.priority == 2
    end
  end

  describe "DownloadWorker" do
    test "uses download queue" do
      changeset = SoundForge.Jobs.DownloadWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.queue == "download"
    end

    test "has max_attempts of 3" do
      changeset = SoundForge.Jobs.DownloadWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.max_attempts == 3
    end

    test "has priority 1" do
      changeset = SoundForge.Jobs.DownloadWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.priority == 1
    end
  end

  describe "CleanupWorker" do
    test "uses default queue (Oban default)" do
      changeset = SoundForge.Jobs.CleanupWorker.new(%{})
      # "default" is the Oban default queue, so it may not appear in changes
      queue = Map.get(changeset.changes, :queue, "default")
      assert queue == "default"
    end

    test "has max_attempts of 1" do
      changeset = SoundForge.Jobs.CleanupWorker.new(%{})
      assert changeset.changes.max_attempts == 1
    end
  end

  describe "ProviderHealthWorker" do
    test "uses analysis queue" do
      changeset = SoundForge.Jobs.ProviderHealthWorker.new(%{"provider_id" => "p1"})
      assert changeset.changes.queue == "analysis"
    end

    test "has max_attempts of 2" do
      changeset = SoundForge.Jobs.ProviderHealthWorker.new(%{"provider_id" => "p1"})
      assert changeset.changes.max_attempts == 2
    end
  end

  describe "LalalAIWorker" do
    test "uses processing queue" do
      changeset = SoundForge.Jobs.LalalAIWorker.new(%{"track_id" => "t1"})
      assert changeset.changes.queue == "processing"
    end
  end
end
