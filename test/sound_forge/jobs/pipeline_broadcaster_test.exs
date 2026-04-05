defmodule SoundForge.Jobs.PipelineBroadcasterTest do
  @moduledoc """
  Tests for PipelineBroadcaster public API: broadcasting progress,
  stage started/complete/failed, and pipeline complete events via PubSub.
  """
  use SoundForge.DataCase

  import SoundForge.MusicFixtures

  alias SoundForge.Jobs.PipelineBroadcaster

  setup %{} do
    user = SoundForge.AccountsFixtures.user_fixture()

    track =
      track_fixture(%{
        user_id: user.id,
        title: "Broadcaster Track",
        artist: "Test Artist",
        duration: 180
      })

    pj =
      processing_job_fixture(%{
        track_id: track.id,
        model: "htdemucs",
        status: :queued
      })

    %{track: track, job: pj, user: user}
  end

  describe "broadcast_progress/3" do
    test "broadcasts to jobs topic", %{job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{job.id}")
      assert :ok = PipelineBroadcaster.broadcast_progress(job.id, :processing, 50)

      assert_receive {:job_progress, %{job_id: _, status: :processing, progress: 50}}
    end

    test "broadcasts completed status", %{job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{job.id}")
      assert :ok = PipelineBroadcaster.broadcast_progress(job.id, :completed, 100)
      assert_receive {:job_progress, %{status: :completed, progress: 100}}
    end
  end

  describe "broadcast_track_progress/4" do
    test "broadcasts to track pipeline topic with title", %{track: track} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")

      assert :ok =
               PipelineBroadcaster.broadcast_track_progress(
                 track.id,
                 :download,
                 :downloading,
                 25
               )

      assert_receive {:pipeline_progress,
                      %{
                        track_id: _,
                        track_title: "Broadcaster Track",
                        stage: :download,
                        status: :downloading,
                        progress: 25
                      }}
    end

    test "uses 'Unknown Track' for missing track" do
      fake_id = Ecto.UUID.generate()
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{fake_id}")

      assert :ok =
               PipelineBroadcaster.broadcast_track_progress(
                 fake_id,
                 :processing,
                 :processing,
                 10
               )

      assert_receive {:pipeline_progress, %{track_title: "Unknown Track"}}
    end
  end

  describe "broadcast_stage_started/3" do
    test "broadcasts stage started events", %{track: track, job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{job.id}")
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")

      assert :ok = PipelineBroadcaster.broadcast_stage_started(track.id, job.id, :download)

      assert_receive {:job_progress, %{status: :downloading, progress: 0}}
      assert_receive {:pipeline_progress, %{stage: :download, status: :downloading, progress: 0}}
    end

    test "maps processing stage to status", %{track: track, job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{job.id}")
      assert :ok = PipelineBroadcaster.broadcast_stage_started(track.id, job.id, :processing)
      assert_receive {:job_progress, %{status: :processing}}
    end

    test "maps analysis stage to status", %{track: track, job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{job.id}")
      assert :ok = PipelineBroadcaster.broadcast_stage_started(track.id, job.id, :analysis)
      assert_receive {:job_progress, %{status: :analyzing}}
    end
  end

  describe "broadcast_stage_complete/3" do
    test "broadcasts completion to both topics", %{track: track, job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{job.id}")
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")

      assert :ok = PipelineBroadcaster.broadcast_stage_complete(track.id, job.id, :download)

      assert_receive {:job_progress, %{status: :completed, progress: 100}}

      assert_receive {:pipeline_progress,
                      %{stage: :download, status: :completed, progress: 100}}
    end

    test "pushes notification for processing complete", %{track: track, job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "notifications:#{track.user_id}")

      PipelineBroadcaster.broadcast_stage_complete(track.id, job.id, :processing)

      assert_receive {:new_notification,
                      %{
                        type: :success,
                        title: "Stem Separation Complete"
                      }}
    end

    test "pushes notification for analysis complete", %{track: track, job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "notifications:#{track.user_id}")
      PipelineBroadcaster.broadcast_stage_complete(track.id, job.id, :analysis)

      assert_receive {:new_notification,
                      %{
                        type: :success,
                        title: "Analysis Complete"
                      }}
    end
  end

  describe "broadcast_stage_failed/3" do
    test "broadcasts failure to both topics", %{track: track, job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{job.id}")
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")

      assert :ok = PipelineBroadcaster.broadcast_stage_failed(track.id, job.id, :download)

      assert_receive {:job_progress, %{status: :failed, progress: 0}}
      assert_receive {:pipeline_progress, %{stage: :download, status: :failed, progress: 0}}
    end

    test "pushes error notification for download failure", %{track: track, job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "notifications:#{track.user_id}")
      PipelineBroadcaster.broadcast_stage_failed(track.id, job.id, :download)

      assert_receive {:new_notification,
                      %{
                        type: :error,
                        title: "Download Failed"
                      }}
    end

    test "pushes error notification for processing failure", %{track: track, job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "notifications:#{track.user_id}")
      PipelineBroadcaster.broadcast_stage_failed(track.id, job.id, :processing)

      assert_receive {:new_notification,
                      %{
                        type: :error,
                        title: "Stem Separation Failed"
                      }}
    end
  end

  describe "broadcast_pipeline_complete/1" do
    test "broadcasts pipeline_complete event", %{track: track} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "track_pipeline:#{track.id}")

      assert :ok = PipelineBroadcaster.broadcast_pipeline_complete(track.id)

      assert_receive {:pipeline_complete,
                      %{track_id: _, track_title: "Broadcaster Track"}}
    end

    test "pushes success notification", %{track: track} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "notifications:#{track.user_id}")
      PipelineBroadcaster.broadcast_pipeline_complete(track.id)

      assert_receive {:new_notification,
                      %{
                        type: :success,
                        title: "Pipeline Complete"
                      }}
    end
  end

  describe "generic stage notification" do
    test "handles unknown stage with info type", %{track: track, job: job} do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "notifications:#{track.user_id}")
      PipelineBroadcaster.broadcast_stage_complete(track.id, job.id, :custom_stage)

      assert_receive {:new_notification, %{type: :info}}
    end
  end
end
