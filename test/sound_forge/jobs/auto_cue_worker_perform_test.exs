defmodule SoundForge.Jobs.AutoCueWorkerPerformTest do
  @moduledoc "Tests for AutoCueWorker perform/1 code paths."
  use SoundForge.DataCase

  alias SoundForge.Jobs.AutoCueWorker

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  describe "perform/1" do
    test "returns error when track has no completed download" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})

      oban_job = %Oban.Job{
        args: %{"track_id" => track.id, "user_id" => user.id},
        attempt: 1
      }

      result = AutoCueWorker.perform(oban_job)
      assert {:error, _reason} = result
    end

    test "returns error when download exists but file not on disk" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})

      download_job_fixture(%{
        track_id: track.id,
        status: :completed,
        output_path: "priv/uploads/downloads/nonexistent_file_#{System.unique_integer()}.mp3"
      })

      oban_job = %Oban.Job{
        args: %{"track_id" => track.id, "user_id" => user.id},
        attempt: 1
      }

      result = AutoCueWorker.perform(oban_job)
      assert {:error, msg} = result
      assert msg =~ "not found" or msg =~ "no_completed_download"
    end
  end
end
