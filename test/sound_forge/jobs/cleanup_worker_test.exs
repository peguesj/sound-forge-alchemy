defmodule SoundForge.Jobs.CleanupWorkerTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.CleanupWorker

  test "perform/1 runs cleanup successfully" do
    SoundForge.Storage.ensure_directories!()
    job = %Oban.Job{args: %{}}
    assert :ok = CleanupWorker.perform(job)
  end
end
