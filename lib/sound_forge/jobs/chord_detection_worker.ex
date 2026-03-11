defmodule SoundForge.Jobs.ChordDetectionWorker do
  @moduledoc """
  Oban worker for chord detection using librosa via ChordDetectorPort.

  Processes an audio file, detects chord progressions and key, and stores the result.
  """
  use Oban.Worker,
    queue: :analysis,
    max_attempts: 3,
    priority: 2

  alias SoundForge.Audio.{ChordDetectorPort, PortSupervisor}
  alias SoundForge.Jobs.PipelineBroadcaster
  alias SoundForge.Music
  alias SoundForge.Storage

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "track_id" => track_id,
          "file_path" => file_path
        }
      }) do
    Logger.metadata(track_id: track_id, worker: "ChordDetectionWorker")
    Logger.info("Starting chord detection")

    resolved_path = Storage.resolve_path(file_path)

    if File.exists?(resolved_path) do
      do_detect(track_id, resolved_path)
    else
      Logger.error("Audio file not found: #{resolved_path}")
      {:error, "Audio file not found: #{resolved_path}"}
    end
  end

  defp do_detect(track_id, file_path) do
    result =
      try do
        {:ok, port_pid} = PortSupervisor.start_chord_detector()
        ChordDetectorPort.detect(file_path, server: port_pid)
      catch
        :exit, reason ->
          {:error, "Port process crashed: #{inspect(reason)}"}
      end

    case result do
      {:ok, %{"chords" => chords, "key" => key}} ->
        {:ok, _chord_result} =
          Music.upsert_chord_result(%{
            track_id: track_id,
            chords: chords,
            key: key
          })

        Logger.info("Chord detection complete: #{length(chords)} chords, key=#{key}")

        Phoenix.PubSub.broadcast(
          SoundForge.PubSub,
          "tracks:#{track_id}",
          {:chord_detection_complete, track_id}
        )

        PipelineBroadcaster.broadcast_pipeline_complete(track_id)
        :ok

      {:error, reason} ->
        Logger.error("Chord detection failed: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end
end
