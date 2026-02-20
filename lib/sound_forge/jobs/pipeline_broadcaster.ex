defmodule SoundForge.Jobs.PipelineBroadcaster do
  @moduledoc """
  Shared broadcasting utilities for pipeline workers.

  Consolidates PubSub broadcasts for job progress, pipeline tracker, and
  user notifications. When a pipeline stage completes or fails, this module
  ensures that:

  1. The job-level topic (`"jobs:{job_id}"`) receives progress updates
     (consumed by the pipeline tracker dropdown).
  2. The track pipeline topic (`"track_pipeline:{track_id}"`) receives
     stage-level progress with track metadata for grouping.
  3. The notifications system (`SoundForge.Notifications`) receives a
     persistent notification for the track's owner (consumed by the
     notification bell dropdown).

  ## Usage

      alias SoundForge.Jobs.PipelineBroadcaster

      # On progress update (no notification pushed)
      PipelineBroadcaster.broadcast_progress(job_id, :processing, 50)

      # On stage completion (pushes notification to track owner)
      PipelineBroadcaster.broadcast_stage_complete(track_id, job_id, :download)

      # On stage failure (pushes error notification to track owner)
      PipelineBroadcaster.broadcast_stage_failed(track_id, job_id, :download)

      # For intermediate progress on pipeline tracker only
      PipelineBroadcaster.broadcast_track_progress(track_id, :download, :downloading, 25)
  """

  alias SoundForge.Music
  alias SoundForge.Notifications

  require Logger

  @doc """
  Broadcasts job-level progress to `"jobs:{job_id}"`.

  This is for the pipeline tracker to show per-job progress bars.
  """
  @spec broadcast_progress(binary(), atom(), non_neg_integer()) :: :ok | {:error, term()}
  def broadcast_progress(job_id, status, progress) do
    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "jobs:#{job_id}",
      {:job_progress, %{job_id: job_id, status: status, progress: progress}}
    )
  end

  @doc """
  Broadcasts track pipeline progress to `"track_pipeline:{track_id}"`.

  Includes track metadata (track_id, track_title) so the UI can group
  pipeline operations by track. The track title is fetched from the database
  and included in the payload.
  """
  @spec broadcast_track_progress(binary(), atom(), atom(), non_neg_integer()) ::
          :ok | {:error, term()}
  def broadcast_track_progress(track_id, stage, status, progress) do
    track_title = fetch_track_title(track_id)

    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "track_pipeline:#{track_id}",
      {:pipeline_progress,
       %{
         track_id: track_id,
         track_title: track_title,
         stage: stage,
         status: status,
         progress: progress
       }}
    )
  end

  @doc """
  Broadcasts a stage completion event and pushes a user notification.

  Sends to both the track pipeline topic (for the pipeline tracker) and
  the notification system (for the notification bell). The notification
  includes track_id, track_title, and stage in its metadata so the UI
  can group notifications by track.
  """
  @spec broadcast_stage_complete(binary(), binary(), atom()) :: :ok
  def broadcast_stage_complete(track_id, job_id, stage) do
    broadcast_progress(job_id, :completed, 100)
    broadcast_track_progress(track_id, stage, :completed, 100)
    push_stage_notification(track_id, stage, :completed)
    :ok
  end

  @doc """
  Broadcasts a stage failure event and pushes an error notification.

  Sends to both the track pipeline topic (for the pipeline tracker) and
  the notification system (for the notification bell).
  """
  @spec broadcast_stage_failed(binary(), binary(), atom()) :: :ok
  def broadcast_stage_failed(track_id, job_id, stage) do
    broadcast_progress(job_id, :failed, 0)
    broadcast_track_progress(track_id, stage, :failed, 0)
    push_stage_notification(track_id, stage, :failed)
    :ok
  end

  @doc """
  Broadcasts that the entire pipeline is complete for a track.

  Sends a `:pipeline_complete` event on the track pipeline topic and
  pushes a final summary notification to the track's owner.
  """
  @spec broadcast_pipeline_complete(binary()) :: :ok
  def broadcast_pipeline_complete(track_id) do
    track_title = fetch_track_title(track_id)

    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "track_pipeline:#{track_id}",
      {:pipeline_complete, %{track_id: track_id, track_title: track_title}}
    )

    push_notification(track_id, %{
      type: :success,
      title: "Pipeline Complete",
      message: "All processing finished for \"#{track_title}\".",
      metadata: %{
        track_id: track_id,
        track_title: track_title,
        stage: :pipeline_complete,
        status: :completed
      }
    })

    :ok
  end

  # -- Private --

  defp push_stage_notification(track_id, stage, status) do
    {type, title, message} = notification_content(stage, status, track_id)

    push_notification(track_id, %{
      type: type,
      title: title,
      message: message,
      metadata: %{
        track_id: track_id,
        track_title: fetch_track_title(track_id),
        stage: stage,
        status: status
      }
    })
  end

  defp push_notification(track_id, attrs) do
    case fetch_track_user_id(track_id) do
      nil ->
        Logger.debug(
          "[PipelineBroadcaster] No user_id for track #{track_id}, skipping notification push"
        )

      user_id ->
        Notifications.push(user_id, attrs)
    end
  end

  defp notification_content(:download, :completed, track_id) do
    title = fetch_track_title(track_id)
    {:success, "Download Complete", "\"#{title}\" has been downloaded successfully."}
  end

  defp notification_content(:download, :failed, track_id) do
    title = fetch_track_title(track_id)
    {:error, "Download Failed", "Failed to download \"#{title}\"."}
  end

  defp notification_content(:processing, :completed, track_id) do
    title = fetch_track_title(track_id)
    {:success, "Stem Separation Complete", "\"#{title}\" stems are ready."}
  end

  defp notification_content(:processing, :failed, track_id) do
    title = fetch_track_title(track_id)
    {:error, "Stem Separation Failed", "Failed to separate stems for \"#{title}\"."}
  end

  defp notification_content(:analysis, :completed, track_id) do
    title = fetch_track_title(track_id)
    {:success, "Analysis Complete", "Audio analysis finished for \"#{title}\"."}
  end

  defp notification_content(:analysis, :failed, track_id) do
    title = fetch_track_title(track_id)
    {:error, "Analysis Failed", "Audio analysis failed for \"#{title}\"."}
  end

  defp notification_content(stage, status, track_id) do
    title = fetch_track_title(track_id)
    type = if status == :completed, do: :info, else: :error
    {type, "#{humanize_stage(stage)} #{status}", "\"#{title}\" - #{stage} #{status}."}
  end

  defp humanize_stage(stage) do
    stage
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp fetch_track_title(track_id) do
    case Music.get_track(track_id) do
      {:ok, %{title: title}} when is_binary(title) and title != "" -> title
      _ -> "Unknown Track"
    end
  rescue
    _ -> "Unknown Track"
  end

  defp fetch_track_user_id(track_id) do
    case Music.get_track(track_id) do
      {:ok, %{user_id: user_id}} when not is_nil(user_id) -> user_id
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
