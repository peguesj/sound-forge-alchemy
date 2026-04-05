defmodule SoundForge.Jobs.DemuserWorkerPerformTest do
  @moduledoc "Tests for DemuserWorker perform/1 code paths."
  use SoundForge.DataCase

  alias SoundForge.Jobs.DemuserWorker

  import SoundForge.MusicFixtures

  describe "perform/1 - missing processing job" do
    test "raises Ecto.NoResultsError when processing job was deleted" do
      track = track_fixture()
      fake_job_id = Ecto.UUID.generate()

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => fake_job_id,
          "file_path" => "priv/uploads/downloads/test.mp3"
        },
        attempt: 1
      }

      assert_raise Ecto.NoResultsError, fn ->
        DemuserWorker.perform(oban_job)
      end
    end
  end

  describe "perform/1 - file not found" do
    test "raises when audio file does not exist" do
      track = track_fixture()

      pj =
        processing_job_fixture(%{
          track_id: track.id,
          model: "demuser",
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
        DemuserWorker.perform(oban_job)
      end
    end

    test "exercises encoder_format option" do
      track = track_fixture()

      pj =
        processing_job_fixture(%{
          track_id: track.id,
          model: "demuser",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "priv/uploads/downloads/missing_#{System.unique_integer()}.mp3",
          "splitter" => "phoenix",
          "encoder_format" => "flac"
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        DemuserWorker.perform(oban_job)
      end
    end
  end
end
