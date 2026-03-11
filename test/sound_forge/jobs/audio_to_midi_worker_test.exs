defmodule SoundForge.Jobs.AudioToMidiWorkerTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.AudioToMidiWorker

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
          "file_path" => "/nonexistent/audio.mp3"
        }
      }

      assert {:error, "Audio file not found:" <> _} = AudioToMidiWorker.perform(job)
    end
  end

  describe "perform/1 - port failure" do
    test "handles port crash gracefully", %{track: track} do
      tmp_file =
        Path.join(System.tmp_dir!(), "midi_test_#{System.unique_integer([:positive])}.mp3")

      File.write!(tmp_file, "ID3" <> :crypto.strong_rand_bytes(512))
      on_exit(fn -> File.rm(tmp_file) end)

      Phoenix.PubSub.subscribe(SoundForge.PubSub, "tracks:#{track.id}")

      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "file_path" => tmp_file
        }
      }

      # Port will fail (basic-pitch likely not installed in test env)
      result = AudioToMidiWorker.perform(job)

      case result do
        {:error, _reason} ->
          # Expected: port failed
          assert true

        :ok ->
          # If basic-pitch is installed, conversion succeeded
          assert_received {:midi_conversion_complete, _}
      end
    end
  end
end
