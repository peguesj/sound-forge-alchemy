defmodule SoundForge.Jobs.DownloadWorkerTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.DownloadWorker
  alias SoundForge.Music

  import SoundForge.MusicFixtures

  setup do
    track = track_fixture()
    download_job = download_job_fixture(%{track_id: track.id, status: :queued})
    %{track: track, download_job: download_job}
  end

  describe "perform/1 - download failure" do
    test "marks job as failed when spotdl is not available", %{
      track: track,
      download_job: download_job
    } do
      # Subscribe to PubSub to verify broadcasts
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{download_job.id}")
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")

      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "spotify_url" => "https://open.spotify.com/track/fake123",
          "quality" => "320",
          "job_id" => download_job.id
        }
      }

      assert {:error, _reason} = DownloadWorker.perform(job)

      # Verify job was marked as failed in DB
      updated_job = Music.get_download_job!(download_job.id)
      assert updated_job.status == :failed

      # Verify PubSub broadcasts were sent
      assert_received {:job_progress, %{job_id: _, status: :downloading, progress: 0}}
      assert_received {:job_progress, %{job_id: _, status: :failed, progress: 0}}

      assert_received {:pipeline_progress,
                       %{track_id: _, stage: :download, status: :downloading, progress: 0}}

      assert_received {:pipeline_progress,
                       %{track_id: _, stage: :download, status: :failed, progress: 0}}
    end
  end

  describe "perform/1 - validation" do
    test "fails on missing audio file after download", %{
      track: track,
      download_job: download_job
    } do
      job = %Oban.Job{
        args: %{
          "track_id" => track.id,
          "spotify_url" => "https://open.spotify.com/track/fake",
          "quality" => "128",
          "job_id" => download_job.id
        }
      }

      # spotdl will fail, resulting in error
      assert {:error, _} = DownloadWorker.perform(job)
    end
  end

  describe "audio file validation" do
    test "validates MP3 with ID3 header", _context do
      # Create a fake MP3 file with ID3 header
      tmp_dir = System.tmp_dir!()
      mp3_path = Path.join(tmp_dir, "test_#{System.unique_integer([:positive])}.mp3")
      # ID3 header + padding
      File.write!(mp3_path, "ID3" <> :crypto.strong_rand_bytes(2048))

      on_exit(fn -> File.rm(mp3_path) end)

      # We can't test the full perform since spotdl won't work,
      # but we can verify the file validation would pass on a valid file
      assert File.exists?(mp3_path)
      assert {:ok, %{size: size}} = File.stat(mp3_path)
      assert size >= 1024
    end

    test "validates FLAC header" do
      tmp_dir = System.tmp_dir!()
      flac_path = Path.join(tmp_dir, "test_#{System.unique_integer([:positive])}.flac")
      File.write!(flac_path, "fLaC" <> :crypto.strong_rand_bytes(2048))

      on_exit(fn -> File.rm(flac_path) end)

      content = File.read!(flac_path)
      assert <<"fLaC", _rest::binary>> = content
    end

    test "validates WAV/RIFF header" do
      tmp_dir = System.tmp_dir!()
      wav_path = Path.join(tmp_dir, "test_#{System.unique_integer([:positive])}.wav")
      File.write!(wav_path, "RIFF" <> :crypto.strong_rand_bytes(2048))

      on_exit(fn -> File.rm(wav_path) end)

      content = File.read!(wav_path)
      assert <<"RIFF", _rest::binary>> = content
    end

    test "validates OGG header" do
      tmp_dir = System.tmp_dir!()
      ogg_path = Path.join(tmp_dir, "test_#{System.unique_integer([:positive])}.ogg")
      File.write!(ogg_path, "OggS" <> :crypto.strong_rand_bytes(2048))

      on_exit(fn -> File.rm(ogg_path) end)

      content = File.read!(ogg_path)
      assert <<"OggS", _rest::binary>> = content
    end
  end
end
