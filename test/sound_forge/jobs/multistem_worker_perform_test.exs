defmodule SoundForge.Jobs.MultiStemWorkerPerformTest do
  @moduledoc "Tests for MultiStemWorker perform/1 code paths."
  use SoundForge.DataCase

  alias SoundForge.Jobs.MultiStemWorker

  import SoundForge.MusicFixtures

  describe "perform/1 - missing processing job" do
    test "raises Ecto.NoResultsError when processing job was deleted" do
      track = track_fixture()
      fake_job_id = Ecto.UUID.generate()

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => fake_job_id,
          "file_path" => "priv/uploads/downloads/test.mp3",
          "stem_list" => ["vocals", "drums"]
        },
        attempt: 1
      }

      assert_raise Ecto.NoResultsError, fn ->
        MultiStemWorker.perform(oban_job)
      end
    end
  end

  describe "perform/1 - file not found" do
    test "raises when audio file does not exist" do
      track = track_fixture()

      pj =
        processing_job_fixture(%{
          track_id: track.id,
          model: "multistem",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "priv/uploads/downloads/nonexistent_#{System.unique_integer()}.mp3",
          "stem_list" => ["vocals", "drums", "bass"]
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        MultiStemWorker.perform(oban_job)
      end
    end
  end
end
