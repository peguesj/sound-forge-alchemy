defmodule SoundForge.Jobs.AnalysisWorkerTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.AnalysisWorker
  alias SoundForge.Music

  import SoundForge.MusicFixtures

  setup do
    track = track_fixture()
    analysis_job = analysis_job_fixture(%{track_id: track.id, status: :queued})
    %{track: track, analysis_job: analysis_job}
  end

  describe "perform/1 - file not found" do
    test "marks job as failed when audio file does not exist", %{
      track: track,
      analysis_job: analysis_job
    } do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{analysis_job.id}")
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")

      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => analysis_job.id,
          "file_path" => "/nonexistent.mp3",
          "features" => ["tempo", "key", "energy"]
        }
      }

      assert {:error, "Audio file not found: /nonexistent.mp3"} = AnalysisWorker.perform(job)

      # Verify DB status updated
      updated_job = Music.get_analysis_job!(analysis_job.id)
      assert updated_job.status == :failed
      assert updated_job.error =~ "Audio file not found"

      # Verify PubSub broadcasts
      assert_received {:job_progress, %{job_id: _, status: :processing, progress: 0}}
      assert_received {:job_progress, %{job_id: _, status: :failed, progress: 0}}

      assert_received {:pipeline_progress,
                       %{track_id: _, stage: :analysis, status: :processing, progress: 0}}

      assert_received {:pipeline_progress,
                       %{track_id: _, stage: :analysis, status: :failed, progress: 0}}
    end
  end

  describe "perform/1 - port failure" do
    test "marks job as failed when analyzer port fails", %{
      track: track,
      analysis_job: analysis_job
    } do
      # Create a real file so we pass the exists? check
      tmp_file = Path.join(System.tmp_dir!(), "analysis_test_#{System.unique_integer([:positive])}.mp3")
      File.write!(tmp_file, "ID3" <> :crypto.strong_rand_bytes(1024))
      on_exit(fn -> File.rm(tmp_file) end)

      Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{analysis_job.id}")

      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => analysis_job.id,
          "file_path" => tmp_file,
          "features" => ["tempo", "key", "energy"]
        }
      }

      # Port will fail since librosa is likely not installed in test
      result = AnalysisWorker.perform(job)

      case result do
        {:error, _reason} ->
          updated_job = Music.get_analysis_job!(analysis_job.id)
          assert updated_job.status == :failed

        :ok ->
          # Unlikely but possible if librosa is available
          :ok
      end

      # Initial processing broadcast should have been sent
      assert_received {:job_progress, %{job_id: _, status: :processing, progress: 0}}
    end
  end

  describe "perform/1 - job status transitions" do
    test "transitions from queued through processing states", %{
      track: track,
      analysis_job: analysis_job
    } do
      assert analysis_job.status == :queued

      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => analysis_job.id,
          "file_path" => "/nonexistent.mp3",
          "features" => ["tempo"]
        }
      }

      AnalysisWorker.perform(job)

      # Should end up failed (file doesn't exist)
      updated = Music.get_analysis_job!(analysis_job.id)
      assert updated.status == :failed
    end
  end
end
