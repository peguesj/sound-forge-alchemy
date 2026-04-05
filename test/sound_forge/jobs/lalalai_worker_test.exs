defmodule SoundForge.Jobs.LalalAIWorkerTest do
  @moduledoc """
  Tests for LalalAIWorker perform/1: nil ProcessingJob guard and
  file-not-found error path.
  """
  use SoundForge.DataCase

  import SoundForge.MusicFixtures

  alias SoundForge.Jobs.LalalAIWorker

  setup do
    user = SoundForge.AccountsFixtures.user_fixture()

    track =
      track_fixture(%{
        user_id: user.id,
        title: "LalalAI Test Track",
        artist: "Test",
        duration: 200
      })

    %{track: track, user: user}
  end

  describe "perform/1 with deleted ProcessingJob" do
    test "returns :ok when ProcessingJob doesn't exist", %{track: track} do
      fake_job_id = Ecto.UUID.generate()

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => fake_job_id,
          "file_path" => "priv/uploads/test.mp3"
        },
        attempt: 1
      }

      assert :ok = LalalAIWorker.perform(oban_job)
    end
  end

  describe "perform/1 with missing file" do
    test "raises when audio file not found", %{track: track} do
      pj =
        processing_job_fixture(%{
          track_id: track.id,
          model: "htdemucs",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "/nonexistent/audio_file.mp3"
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        LalalAIWorker.perform(oban_job)
      end

      updated = SoundForge.Music.get_processing_job!(pj.id)
      assert updated.status == :failed
      assert updated.error =~ "Audio file not found"
    end
  end

  describe "new/1" do
    test "creates valid changeset with all options" do
      changeset =
        LalalAIWorker.new(%{
          "track_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "test.mp3",
          "stem_filter" => "drums",
          "preview" => true,
          "splitter" => "phoenix",
          "multivocal" => "lead_back"
        })

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end
end
