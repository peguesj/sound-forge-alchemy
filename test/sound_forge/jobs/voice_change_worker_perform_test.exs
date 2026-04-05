defmodule SoundForge.Jobs.VoiceChangeWorkerPerformTest do
  @moduledoc "Tests for VoiceChangeWorker perform/1 code paths."
  use SoundForge.DataCase

  alias SoundForge.Jobs.VoiceChangeWorker

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
          "voice_pack_id" => "builtin_male_1"
        },
        attempt: 1
      }

      assert_raise Ecto.NoResultsError, fn ->
        VoiceChangeWorker.perform(oban_job)
      end
    end
  end

  describe "perform/1 - file not found" do
    test "raises when audio file does not exist" do
      track = track_fixture()

      pj =
        processing_job_fixture(%{
          track_id: track.id,
          model: "voice_change",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "priv/uploads/downloads/nonexistent_#{System.unique_integer()}.mp3",
          "voice_pack_id" => "builtin_female_1"
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        VoiceChangeWorker.perform(oban_job)
      end
    end

    test "exercises accent and tonality_reference options" do
      track = track_fixture()

      pj =
        processing_job_fixture(%{
          track_id: track.id,
          model: "voice_change",
          status: :queued
        })

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "priv/uploads/downloads/missing_#{System.unique_integer()}.mp3",
          "voice_pack_id" => "custom_pack",
          "accent" => 0.8,
          "tonality_reference" => "voice_pack",
          "dereverb" => true,
          "encoder_format" => "mp3"
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        VoiceChangeWorker.perform(oban_job)
      end
    end
  end
end
