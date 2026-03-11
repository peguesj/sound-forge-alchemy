defmodule SoundForge.Jobs.AutoCueWorkerTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.AutoCueWorker

  import SoundForge.MusicFixtures

  describe "perform/1 - file not found" do
    test "returns error when no completed download exists" do
      track = track_fixture()

      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "user_id" => 1
        }
      }

      assert {:error, _} = AutoCueWorker.perform(job)
    end
  end
end
