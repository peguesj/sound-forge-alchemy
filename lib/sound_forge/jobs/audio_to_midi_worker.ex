defmodule SoundForge.Jobs.AudioToMidiWorker do
  @moduledoc """
  Oban worker for audio-to-MIDI conversion using basic-pitch via AudioToMidiPort.

  Processes an audio file, extracts MIDI note data, and stores the result.
  """
  use Oban.Worker,
    queue: :analysis,
    max_attempts: 3,
    priority: 2

  alias SoundForge.Audio.{AudioToMidiPort, PortSupervisor}
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
    Logger.metadata(track_id: track_id, worker: "AudioToMidiWorker")
    Logger.info("Starting audio-to-MIDI conversion")

    resolved_path = Storage.resolve_path(file_path)

    if File.exists?(resolved_path) do
      do_convert(track_id, resolved_path)
    else
      Logger.error("Audio file not found: #{resolved_path}")
      {:error, "Audio file not found: #{resolved_path}"}
    end
  end

  defp do_convert(track_id, file_path) do
    result =
      try do
        {:ok, port_pid} = PortSupervisor.start_audio_to_midi()
        AudioToMidiPort.convert(file_path, server: port_pid)
      catch
        :exit, reason ->
          {:error, "Port process crashed: #{inspect(reason)}"}
      end

    case result do
      {:ok, notes} ->
        {:ok, _midi_result} =
          Music.upsert_midi_result(%{
            track_id: track_id,
            notes: notes
          })

        Logger.info("Audio-to-MIDI complete: #{length(notes)} notes detected")

        Phoenix.PubSub.broadcast(
          SoundForge.PubSub,
          "tracks:#{track_id}",
          {:midi_conversion_complete, track_id}
        )

        PipelineBroadcaster.broadcast_pipeline_complete(track_id)
        :ok

      {:error, reason} ->
        Logger.error("Audio-to-MIDI failed: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end
end
