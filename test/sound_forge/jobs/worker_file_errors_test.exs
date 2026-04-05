defmodule SoundForge.Jobs.WorkerFileErrorsTest do
  @moduledoc """
  Tests for worker perform/1 error paths: missing audio files.
  Each lalal.ai-based worker raises when the audio file doesn't exist.
  """
  use SoundForge.DataCase

  import SoundForge.MusicFixtures

  alias SoundForge.Jobs.{
    DemuserWorker,
    MultiStemWorker,
    VoiceChangeWorker,
    VoiceCleanWorker
  }

  setup do
    user = SoundForge.AccountsFixtures.user_fixture()

    track =
      track_fixture(%{
        user_id: user.id,
        title: "File Error Track",
        artist: "Test",
        duration: 120
      })

    pj =
      processing_job_fixture(%{
        track_id: track.id,
        model: "htdemucs",
        status: :queued
      })

    %{track: track, job: pj}
  end

  describe "VoiceCleanWorker with missing file" do
    test "raises when audio file not found", %{track: track, job: pj} do
      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "/nonexistent/voice_clean.mp3"
        }
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        VoiceCleanWorker.perform(oban_job)
      end

      updated = SoundForge.Music.get_processing_job!(pj.id)
      assert updated.status == :failed
    end
  end

  describe "DemuserWorker with missing file" do
    test "raises when audio file not found", %{track: track} do
      pj2 =
        processing_job_fixture(%{
          track_id: track.id,
          model: "htdemucs",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj2.id,
          "file_path" => "/nonexistent/demuser.mp3"
        }
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        DemuserWorker.perform(oban_job)
      end

      updated = SoundForge.Music.get_processing_job!(pj2.id)
      assert updated.status == :failed
    end
  end

  describe "MultiStemWorker with missing file" do
    test "raises when audio file not found", %{track: track} do
      pj3 =
        processing_job_fixture(%{
          track_id: track.id,
          model: "htdemucs",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj3.id,
          "file_path" => "/nonexistent/multistem.mp3",
          "stem_list" => ["vocals", "drums"]
        }
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        MultiStemWorker.perform(oban_job)
      end

      updated = SoundForge.Music.get_processing_job!(pj3.id)
      assert updated.status == :failed
    end
  end

  describe "VoiceChangeWorker with missing file" do
    test "raises when audio file not found", %{track: track} do
      pj4 =
        processing_job_fixture(%{
          track_id: track.id,
          model: "htdemucs",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj4.id,
          "file_path" => "/nonexistent/voice_change.mp3",
          "voice_pack_id" => "ALEX_KAYE"
        }
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        VoiceChangeWorker.perform(oban_job)
      end

      updated = SoundForge.Music.get_processing_job!(pj4.id)
      assert updated.status == :failed
    end
  end
end
