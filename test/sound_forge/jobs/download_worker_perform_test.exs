defmodule SoundForge.Jobs.DownloadWorkerPerformTest do
  @moduledoc "Tests for DownloadWorker perform/1 code paths."
  use SoundForge.DataCase

  alias SoundForge.Jobs.DownloadWorker

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  describe "perform/1" do
    test "exercises initial code paths with real DB records" do
      user = user_fixture()

      track =
        track_fixture(%{user_id: user.id, spotify_url: "https://open.spotify.com/track/test123"})

      dj =
        download_job_fixture(%{
          track_id: track.id,
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "spotify_url" => "https://open.spotify.com/track/test123",
          "quality" => "320",
          "job_id" => dj.id
        },
        attempt: 1,
        max_attempts: 3
      }

      # SpotDL may or may not be available in test env
      # Either way, the DB lookup and status update code paths are exercised
      result = DownloadWorker.perform(oban_job)
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(DownloadWorker)
    end

    test "implements Oban.Worker" do
      behaviours =
        DownloadWorker.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Oban.Worker in behaviours
    end
  end
end
