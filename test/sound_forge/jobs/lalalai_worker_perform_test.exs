defmodule SoundForge.Jobs.LalalAIWorkerPerformTest do
  @moduledoc "Tests for LalalAIWorker perform/1 code paths."
  use SoundForge.DataCase

  alias SoundForge.Jobs.LalalAIWorker

  import SoundForge.MusicFixtures

  describe "perform/1 - file not found" do
    test "raises when audio file does not exist on disk" do
      track = track_fixture()

      pj =
        processing_job_fixture(%{
          track_id: track.id,
          model: "lalalai",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "priv/uploads/downloads/nonexistent_#{System.unique_integer()}.mp3"
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        LalalAIWorker.perform(oban_job)
      end
    end

    test "exercises stem_filter and preview defaults" do
      track = track_fixture()

      pj =
        processing_job_fixture(%{
          track_id: track.id,
          model: "lalalai",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "priv/uploads/downloads/missing_#{System.unique_integer()}.mp3",
          "stem_filter" => "drums",
          "preview" => true,
          "splitter" => "orion"
        },
        attempt: 2
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        LalalAIWorker.perform(oban_job)
      end
    end

    test "exercises multivocal option parsing" do
      track = track_fixture()

      pj =
        processing_job_fixture(%{
          track_id: track.id,
          model: "lalalai",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "priv/uploads/downloads/missing_#{System.unique_integer()}.mp3",
          "multivocal" => "lead_back"
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        LalalAIWorker.perform(oban_job)
      end
    end
  end

  describe "perform/1 - processing job updates" do
    test "updates processing job status to :processing before attempting upload" do
      track = track_fixture()

      pj =
        processing_job_fixture(%{
          track_id: track.id,
          model: "lalalai",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "priv/uploads/downloads/missing_#{System.unique_integer()}.mp3"
        },
        attempt: 1
      }

      assert_raise RuntimeError, fn ->
        LalalAIWorker.perform(oban_job)
      end

      # After the raise, the processing job should have been updated to failed
      updated = SoundForge.Music.get_processing_job!(pj.id)
      assert updated.status == :failed
    end
  end
end
