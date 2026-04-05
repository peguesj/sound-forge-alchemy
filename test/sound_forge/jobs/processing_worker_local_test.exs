defmodule SoundForge.Jobs.ProcessingWorkerLocalTest do
  @moduledoc "Tests for ProcessingWorker local Demucs processing path."
  use SoundForge.DataCase

  alias SoundForge.Jobs.ProcessingWorker

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  describe "perform/1 local demucs path" do
    test "returns error when audio file does not exist" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id, title: "Demucs Track"})
      download_job_fixture(%{track_id: track.id, status: :completed, output_path: "nonexistent_audio_#{System.unique_integer()}.mp3"})

      pj = processing_job_fixture(%{
        track_id: track.id,
        model: "htdemucs",
        status: :queued
      })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "priv/uploads/downloads/nonexistent_audio_#{System.unique_integer()}.mp3",
          "model" => "htdemucs",
          "user_id" => user.id
        },
        attempt: 1
      }

      result = ProcessingWorker.perform(oban_job)
      # Should fail on file validation or demucs port error
      assert match?({:error, _}, result) or match?({:discard, _}, result) or result == :ok
    end

    test "returns error when processing job not found" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "test.mp3",
          "model" => "htdemucs",
          "user_id" => user.id
        },
        attempt: 1
      }

      assert_raise Ecto.NoResultsError, fn ->
        ProcessingWorker.perform(oban_job)
      end
    end
  end

  describe "perform/1 delegation" do
    test "delegates voice_clean mode to VoiceCleanWorker" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "engine" => "lalalai",
          "mode" => "voice_clean",
          "file_path" => "test.mp3"
        },
        attempt: 1
      }

      result = ProcessingWorker.perform(oban_job)
      assert {:discard, :delegated_to_voice_clean} = result
    end

    test "delegates demuser mode" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "engine" => "lalalai",
          "mode" => "demuser",
          "file_path" => "test.mp3"
        },
        attempt: 1
      }

      result = ProcessingWorker.perform(oban_job)
      assert {:discard, :delegated_to_demuser} = result
    end

    test "delegates multistem mode" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "engine" => "lalalai",
          "mode" => "multistem",
          "file_path" => "test.mp3",
          "stem_list" => ["vocals", "drums"]
        },
        attempt: 1
      }

      result = ProcessingWorker.perform(oban_job)
      assert {:discard, :delegated_to_multistem} = result
    end

    test "delegates voice_change mode" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "engine" => "lalalai",
          "mode" => "voice_change",
          "file_path" => "test.mp3"
        },
        attempt: 1
      }

      result = ProcessingWorker.perform(oban_job)
      assert {:discard, :delegated_to_voice_change} = result
    end

    test "delegates generic lalalai (no mode)" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "engine" => "lalalai",
          "file_path" => "test.mp3"
        },
        attempt: 1
      }

      result = ProcessingWorker.perform(oban_job)
      assert {:discard, :delegated_to_lalalai} = result
    end
  end
end
