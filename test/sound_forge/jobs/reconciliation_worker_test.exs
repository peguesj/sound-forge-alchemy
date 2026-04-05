defmodule SoundForge.Jobs.ReconciliationWorkerTest do
  @moduledoc """
  Tests for ReconciliationWorker perform/1 which audits completed
  download_jobs and verifies files exist on disk.
  """
  use SoundForge.DataCase

  import SoundForge.MusicFixtures

  alias SoundForge.Jobs.ReconciliationWorker

  setup do
    user = SoundForge.AccountsFixtures.user_fixture()

    track =
      track_fixture(%{
        user_id: user.id,
        title: "Reconciliation Track",
        artist: "Test",
        duration: 120
      })

    %{track: track, user: user}
  end

  describe "perform/1" do
    test "runs audit with no completed jobs" do
      oban_job = %Oban.Job{args: %{}}
      assert {:ok, %{valid: 0, invalidated: 0}} = ReconciliationWorker.perform(oban_job)
    end

    test "invalidates completed job with missing file", %{track: track} do
      download_job_fixture(%{
        track_id: track.id,
        status: :completed,
        output_path: "/nonexistent/path/audio.mp3"
      })

      oban_job = %Oban.Job{args: %{}}
      assert {:ok, %{invalidated: invalidated}} = ReconciliationWorker.perform(oban_job)
      assert invalidated >= 1
    end

    test "keeps valid completed job with existing file", %{track: track} do
      tmp = Path.join(System.tmp_dir!(), "reconciliation_test_#{track.id}.wav")
      File.write!(tmp, "RIFF" <> String.duplicate(<<0>>, 2048))

      download_job_fixture(%{
        track_id: track.id,
        status: :completed,
        output_path: tmp
      })

      oban_job = %Oban.Job{args: %{}}
      {:ok, %{valid: valid}} = ReconciliationWorker.perform(oban_job)
      assert valid >= 1

      File.rm(tmp)
    end
  end
end
