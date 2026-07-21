defmodule SoundForge.Jobs.LalalAIWorkersTest do
  @moduledoc """
  Tests for lalal.ai worker modules: LalalAIWorker, VoiceCleanWorker,
  DemuserWorker, VoiceChangeWorker, MultiStemWorker.
  Tests validation paths and early error conditions.
  """
  use SoundForge.DataCase

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  alias SoundForge.Jobs.{
    LalalAIWorker,
    VoiceCleanWorker,
    DemuserWorker,
    VoiceChangeWorker,
    MultiStemWorker
  }

  setup do
    user = user_fixture()
    track = track_fixture(%{user_id: user.id, title: "Worker Test Track"})
    %{user: user, track: track}
  end

  describe "LalalAIWorker" do
    test "module is loaded" do
      assert Code.ensure_loaded?(LalalAIWorker)
    end

    test "implements Oban.Worker" do
      assert {:perform, 1} in LalalAIWorker.__info__(:functions)
    end

    test "perform raises when file not found", %{track: track} do
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "nonexistent/path.mp3"
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        LalalAIWorker.perform(oban_job)
      end
    end

    test "perform with stem_filter option raises on missing file", %{track: track} do
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "nonexistent.mp3",
          "stem_filter" => "drums"
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        LalalAIWorker.perform(oban_job)
      end
    end

    test "perform with preview mode raises on missing file", %{track: track} do
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "nonexistent.mp3",
          "preview" => true
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        LalalAIWorker.perform(oban_job)
      end
    end

    test "perform returns :ok when processing job was deleted", %{track: track} do
      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => Ecto.UUID.generate(),
          "file_path" => "test.mp3"
        },
        attempt: 1
      }

      # LalalAIWorker has a nil check for deleted processing jobs
      assert :ok = LalalAIWorker.perform(oban_job)
    end
  end

  describe "VoiceCleanWorker" do
    test "module is loaded" do
      assert Code.ensure_loaded?(VoiceCleanWorker)
    end

    test "perform raises when file not found", %{track: track} do
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "nonexistent/voice.mp3"
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        VoiceCleanWorker.perform(oban_job)
      end
    end

    test "perform with noise cancelling raises on missing file", %{track: track} do
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "nonexistent.mp3",
          "noise_cancelling_level" => 2
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        VoiceCleanWorker.perform(oban_job)
      end
    end
  end

  describe "DemuserWorker" do
    test "module is loaded" do
      assert Code.ensure_loaded?(DemuserWorker)
    end

    test "perform raises when file not found", %{track: track} do
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "nonexistent/demuser.mp3"
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        DemuserWorker.perform(oban_job)
      end
    end
  end

  describe "VoiceChangeWorker" do
    test "module is loaded" do
      assert Code.ensure_loaded?(VoiceChangeWorker)
    end

    test "perform raises when file not found", %{track: track} do
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "nonexistent/voicechange.mp3",
          "voice_pack_id" => "deep"
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        VoiceChangeWorker.perform(oban_job)
      end
    end
  end

  describe "MultiStemWorker" do
    test "module is loaded" do
      assert Code.ensure_loaded?(MultiStemWorker)
    end

    test "perform raises when file not found", %{track: track} do
      pj = processing_job_fixture(%{track_id: track.id, model: "lalalai", status: :queued})

      oban_job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "job_id" => pj.id,
          "file_path" => "nonexistent/multistem.mp3",
          "stem_list" => ["vocals", "drums"]
        },
        attempt: 1
      }

      assert_raise RuntimeError, ~r/Audio file not found/, fn ->
        MultiStemWorker.perform(oban_job)
      end
    end
  end
end
