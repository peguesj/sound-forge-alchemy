defmodule SoundForge.Jobs.WorkerChangesetTest do
  @moduledoc """
  Tests that all Oban workers correctly produce job changesets via new/1.
  Covers the `use Oban.Worker` configuration for each worker module.
  """
  use SoundForge.DataCase

  alias SoundForge.Jobs.{
    AnalysisWorker,
    AutoCueWorker,
    ChefWorker,
    CleanupWorker,
    DemuserWorker,
    DownloadWorker,
    LalalAIWorker,
    MultiStemWorker,
    ProcessingWorker,
    ProviderHealthWorker,
    ReconciliationWorker,
    VoiceChangeWorker,
    VoiceCleanWorker
  }

  describe "DownloadWorker.new/1" do
    test "creates valid changeset" do
      changeset =
        DownloadWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "spotify_url" => "https://open.spotify.com/track/test",
          "quality" => "320k",
          "job_id" => Ecto.UUID.generate()
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "ProcessingWorker.new/1" do
    test "creates valid changeset" do
      changeset =
        ProcessingWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "priv/uploads/test.mp3",
          "model" => "htdemucs"
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "AnalysisWorker.new/1" do
    test "creates valid changeset" do
      changeset =
        AnalysisWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "priv/uploads/test.mp3",
          "features" => ["tempo", "key"]
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "LalalAIWorker.new/1" do
    test "creates valid changeset" do
      changeset =
        LalalAIWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "priv/uploads/test.mp3",
          "stem_filter" => "vocals"
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "VoiceCleanWorker.new/1" do
    test "creates valid changeset" do
      changeset =
        VoiceCleanWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "priv/uploads/test.mp3",
          "noise_cancelling_level" => 1
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "VoiceChangeWorker.new/1" do
    test "creates valid changeset" do
      changeset =
        VoiceChangeWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "priv/uploads/test.mp3",
          "voice_pack_id" => "ALEX_KAYE"
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "DemuserWorker.new/1" do
    test "creates valid changeset" do
      changeset =
        DemuserWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "priv/uploads/test.mp3"
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "MultiStemWorker.new/1" do
    test "creates valid changeset" do
      changeset =
        MultiStemWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "priv/uploads/test.mp3",
          "stem_list" => ["vocals", "drums", "bass"]
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "AutoCueWorker.new/1" do
    test "creates valid changeset" do
      changeset =
        AutoCueWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "user_id" => 1
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "ChefWorker.new/1" do
    test "creates valid changeset" do
      changeset =
        ChefWorker.new(%{
          "user_id" => 1,
          "track_ids" => [Ecto.UUID.generate()],
          "stem_types" => ["vocals", "drums"],
          "cue_plan" => [],
          "candidate_track_ids" => [],
          "recipe_meta" => %{}
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "ReconciliationWorker.new/1" do
    test "creates valid changeset" do
      changeset = ReconciliationWorker.new(%{})
      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "CleanupWorker.new/1" do
    test "creates valid changeset" do
      changeset = CleanupWorker.new(%{})
      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "ProviderHealthWorker.new/1" do
    test "creates valid changeset" do
      changeset =
        ProviderHealthWorker.new(%{
          "provider_id" => Ecto.UUID.generate()
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end
end
