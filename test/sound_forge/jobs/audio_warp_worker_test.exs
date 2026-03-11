defmodule SoundForge.Jobs.AudioWarpWorkerTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.AudioWarpWorker

  import SoundForge.MusicFixtures

  setup do
    track = track_fixture()
    %{track: track}
  end

  describe "perform/1 - file not found" do
    test "returns error when audio file does not exist", %{track: track} do
      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "file_path" => "/nonexistent/audio.mp3",
          "tempo_factor" => 1.0,
          "pitch_semitones" => 0
        }
      }

      assert {:error, "Audio file not found:" <> _} = AudioWarpWorker.perform(job)
    end
  end

  describe "perform/1 - port failure" do
    test "handles port crash gracefully", %{track: track} do
      tmp_file =
        Path.join(System.tmp_dir!(), "warp_test_#{System.unique_integer([:positive])}.mp3")

      File.write!(tmp_file, "ID3" <> :crypto.strong_rand_bytes(512))
      on_exit(fn -> File.rm(tmp_file) end)

      Phoenix.PubSub.subscribe(SoundForge.PubSub, "tracks:#{track.id}")

      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "file_path" => tmp_file,
          "tempo_factor" => 1.2,
          "pitch_semitones" => 2
        }
      }

      result = AudioWarpWorker.perform(job)

      case result do
        {:error, _reason} ->
          assert true

        :ok ->
          assert_received {:warp_complete, _, _}
      end
    end
  end
end
