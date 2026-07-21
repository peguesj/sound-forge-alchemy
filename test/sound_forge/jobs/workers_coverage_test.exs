defmodule SoundForge.Jobs.WorkersCoverageTest do
  @moduledoc "Tests for Oban worker changesets and error paths for all lalal.ai workers."
  use SoundForge.DataCase

  import SoundForge.MusicFixtures

  alias SoundForge.Jobs.{
    LalalAIWorker,
    DemuserWorker,
    MultiStemWorker,
    VoiceCleanWorker,
    VoiceChangeWorker,
    AutoCueWorker,
    ChefWorker
  }

  setup do
    user = SoundForge.AccountsFixtures.user_fixture()

    track =
      track_fixture(%{user_id: user.id, title: "Worker Test", artist: "Test", duration: 100})

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :queued})
    %{user: user, track: track, pj: pj}
  end

  describe "LalalAIWorker" do
    test "new/1 creates valid changeset" do
      cs = LalalAIWorker.new(%{"track_id" => "t1", "job_id" => "j1", "file_path" => "/tmp/x.mp3"})
      assert cs.valid?
    end

    test "perform with nonexistent file raises", %{track: track, pj: pj} do
      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" =>
            "priv/uploads/downloads/nonexistent_#{System.unique_integer([:positive])}.mp3"
        },
        attempt: 1,
        id: 1,
        worker: "SoundForge.Jobs.LalalAIWorker"
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        LalalAIWorker.perform(job)
      end
    end
  end

  describe "DemuserWorker" do
    test "new/1 creates valid changeset" do
      cs = DemuserWorker.new(%{"track_id" => "t1", "job_id" => "j1", "file_path" => "/tmp/x.mp3"})
      assert cs.valid?
    end

    test "perform with nonexistent file raises", %{track: track, pj: pj} do
      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" =>
            "priv/uploads/downloads/nonexistent_#{System.unique_integer([:positive])}.mp3"
        },
        id: 2,
        worker: "SoundForge.Jobs.DemuserWorker"
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        DemuserWorker.perform(job)
      end
    end
  end

  describe "MultiStemWorker" do
    test "new/1 creates valid changeset" do
      cs =
        MultiStemWorker.new(%{
          "track_id" => "t1",
          "job_id" => "j1",
          "file_path" => "/tmp/x.mp3",
          "stem_list" => ["vocals", "drums"]
        })

      assert cs.valid?
    end

    test "perform with nonexistent file raises", %{track: track, pj: pj} do
      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" =>
            "priv/uploads/downloads/nonexistent_#{System.unique_integer([:positive])}.mp3",
          "stem_list" => ["vocals", "drums"]
        },
        id: 3,
        worker: "SoundForge.Jobs.MultiStemWorker"
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        MultiStemWorker.perform(job)
      end
    end
  end

  describe "VoiceCleanWorker" do
    test "new/1 creates valid changeset" do
      cs =
        VoiceCleanWorker.new(%{"track_id" => "t1", "job_id" => "j1", "file_path" => "/tmp/x.mp3"})

      assert cs.valid?
    end

    test "perform with nonexistent file raises", %{track: track, pj: pj} do
      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" =>
            "priv/uploads/downloads/nonexistent_#{System.unique_integer([:positive])}.mp3"
        },
        id: 4,
        worker: "SoundForge.Jobs.VoiceCleanWorker"
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        VoiceCleanWorker.perform(job)
      end
    end
  end

  describe "VoiceChangeWorker" do
    test "new/1 creates valid changeset" do
      cs =
        VoiceChangeWorker.new(%{
          "track_id" => "t1",
          "job_id" => "j1",
          "file_path" => "/tmp/x.mp3"
        })

      assert cs.valid?
    end

    test "perform with nonexistent file raises", %{track: track, pj: pj} do
      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" =>
            "priv/uploads/downloads/nonexistent_#{System.unique_integer([:positive])}.mp3",
          "voice_pack_id" => "test-pack"
        },
        id: 5,
        worker: "SoundForge.Jobs.VoiceChangeWorker"
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        VoiceChangeWorker.perform(job)
      end
    end
  end

  describe "AutoCueWorker" do
    test "new/1 creates valid changeset" do
      cs = AutoCueWorker.new(%{"track_id" => "t1", "user_id" => 1})
      assert cs.valid?
    end

    test "perform with track that has no download", %{track: _track, user: user} do
      # Create a track without a download
      track2 =
        track_fixture(%{user_id: user.id, title: "No Download", artist: "Test", duration: 50})

      job = %Oban.Job{
        args: %{
          "track_id" => track2.id,
          "user_id" => user.id
        },
        id: 6,
        worker: "SoundForge.Jobs.AutoCueWorker"
      }

      result = AutoCueWorker.perform(job)
      # Should fail because track has no download
      assert match?({:error, _}, result) or match?({:cancel, _}, result)
    end
  end

  describe "ChefWorker" do
    test "new/1 creates valid changeset" do
      cs =
        ChefWorker.new(%{
          "user_id" => 1,
          "track_ids" => ["t1", "t2"],
          "stem_types" => ["vocals"],
          "cue_plan" => %{},
          "candidate_track_ids" => ["t1", "t2", "t3"],
          "recipe_meta" => %{}
        })

      assert cs.valid?
    end
  end
end
