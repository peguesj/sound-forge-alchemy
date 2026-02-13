defmodule SoundForge.JobsTest do
  use SoundForge.DataCase
  use Oban.Testing, repo: SoundForge.Repo

  alias SoundForge.Jobs.DownloadWorker
  alias SoundForge.Jobs.ProcessingWorker
  alias SoundForge.Jobs.AnalysisWorker
  alias SoundForge.Music

  describe "DownloadWorker" do
    test "enqueues a download job" do
      track_id = Ecto.UUID.generate()
      job_id = Ecto.UUID.generate()

      assert {:ok, %Oban.Job{}} =
               DownloadWorker.new(%{
                 "track_id" => track_id,
                 "job_id" => job_id,
                 "spotify_url" => "https://open.spotify.com/track/abc123",
                 "quality" => "320k"
               })
               |> Oban.insert()
    end

    test "job is inserted into download queue" do
      track_id = Ecto.UUID.generate()
      job_id = Ecto.UUID.generate()

      attrs = %{
        "track_id" => track_id,
        "job_id" => job_id,
        "spotify_url" => "https://open.spotify.com/track/abc123",
        "quality" => "320k"
      }

      DownloadWorker.new(attrs) |> Oban.insert()
      assert_enqueued(worker: DownloadWorker, args: attrs)
    end

    test "job has correct queue and priority settings" do
      track_id = Ecto.UUID.generate()
      job_id = Ecto.UUID.generate()

      attrs = %{
        "track_id" => track_id,
        "job_id" => job_id,
        "spotify_url" => "https://open.spotify.com/track/abc123",
        "quality" => "320k"
      }

      {:ok, job} = DownloadWorker.new(attrs) |> Oban.insert()

      assert job.queue == "download"
      assert job.priority == 1
      assert job.max_attempts == 3
    end
  end

  describe "ProcessingWorker" do
    test "enqueues a processing job" do
      {:ok, track} = Music.create_track(%{title: "Test Track"})

      {:ok, processing_job} =
        Music.create_processing_job(%{track_id: track.id, model: "htdemucs", status: :queued})

      attrs = %{
        "track_id" => track.id,
        "job_id" => processing_job.id,
        "file_path" => "/tmp/test.mp3",
        "model" => "htdemucs"
      }

      assert {:ok, %Oban.Job{}} = ProcessingWorker.new(attrs) |> Oban.insert()
      assert_enqueued(worker: ProcessingWorker, args: attrs)
    end

    test "job has correct queue and priority settings" do
      attrs = %{
        "track_id" => Ecto.UUID.generate(),
        "job_id" => Ecto.UUID.generate(),
        "file_path" => "/tmp/test.mp3",
        "model" => "htdemucs"
      }

      {:ok, job} = ProcessingWorker.new(attrs) |> Oban.insert()

      assert job.queue == "processing"
      assert job.priority == 2
      assert job.max_attempts == 2
    end
  end

  describe "AnalysisWorker" do
    test "enqueues an analysis job" do
      {:ok, track} = Music.create_track(%{title: "Test Track"})

      {:ok, analysis_job} =
        Music.create_analysis_job(%{track_id: track.id, status: :queued})

      attrs = %{
        "track_id" => track.id,
        "job_id" => analysis_job.id,
        "file_path" => "/tmp/test.mp3",
        "features" => ["tempo", "key", "energy"]
      }

      assert {:ok, %Oban.Job{}} = AnalysisWorker.new(attrs) |> Oban.insert()
      assert_enqueued(worker: AnalysisWorker, args: attrs)
    end

    test "job has correct queue and priority settings" do
      attrs = %{
        "track_id" => Ecto.UUID.generate(),
        "job_id" => Ecto.UUID.generate(),
        "file_path" => "/tmp/test.mp3",
        "features" => ["tempo", "key"]
      }

      {:ok, job} = AnalysisWorker.new(attrs) |> Oban.insert()

      assert job.queue == "analysis"
      assert job.priority == 2
      assert job.max_attempts == 2
    end
  end

  describe "Pipeline chaining" do
    test "workers enqueue to their expected queues" do
      attrs = %{
        "track_id" => Ecto.UUID.generate(),
        "job_id" => Ecto.UUID.generate(),
        "file_path" => "/tmp/test.mp3",
        "model" => "htdemucs"
      }

      {:ok, processing_job} = ProcessingWorker.new(attrs) |> Oban.insert()
      assert processing_job.queue == "processing"

      analysis_attrs = %{
        "track_id" => Ecto.UUID.generate(),
        "job_id" => Ecto.UUID.generate(),
        "file_path" => "/tmp/test.mp3",
        "features" => ["tempo"]
      }

      {:ok, analysis_job} = AnalysisWorker.new(analysis_attrs) |> Oban.insert()
      assert analysis_job.queue == "analysis"

      download_attrs = %{
        "track_id" => Ecto.UUID.generate(),
        "job_id" => Ecto.UUID.generate(),
        "spotify_url" => "https://open.spotify.com/track/abc",
        "quality" => "320k"
      }

      {:ok, download_job} = DownloadWorker.new(download_attrs) |> Oban.insert()
      assert download_job.queue == "download"
    end
  end
end
