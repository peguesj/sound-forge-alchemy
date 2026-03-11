defmodule SoundForge.Jobs.AudioWarpWorker do
  @moduledoc """
  Oban worker for audio warping (time-stretch / pitch-shift) via AudioWarpPort.

  Processes warp requests, saves warped files, and broadcasts completion.
  """
  use Oban.Worker,
    queue: :processing,
    max_attempts: 3,
    priority: 2

  alias SoundForge.Audio.{AudioWarpPort, PortSupervisor}
  alias SoundForge.Jobs.PipelineBroadcaster
  alias SoundForge.Storage

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "track_id" => track_id,
          "file_path" => file_path,
          "tempo_factor" => tempo_factor,
          "pitch_semitones" => pitch_semitones
        }
      }) do
    Logger.metadata(track_id: track_id, worker: "AudioWarpWorker")
    Logger.info("Starting audio warp: tempo=#{tempo_factor}, pitch=#{pitch_semitones}")

    resolved_path = Storage.resolve_path(file_path)

    if File.exists?(resolved_path) do
      do_warp(track_id, resolved_path, tempo_factor, pitch_semitones)
    else
      Logger.error("Audio file not found: #{resolved_path}")
      {:error, "Audio file not found: #{resolved_path}"}
    end
  end

  defp do_warp(track_id, file_path, tempo_factor, pitch_semitones) do
    # Build output path in warped directory
    warped_dir = Path.join(Storage.base_path(), "warped")
    File.mkdir_p!(warped_dir)

    basename = Path.basename(file_path, Path.extname(file_path))
    output_filename = "#{basename}_t#{tempo_factor}_p#{pitch_semitones}.wav"
    output_path = Path.join(warped_dir, output_filename)

    result =
      try do
        {:ok, port_pid} = PortSupervisor.start_audio_warp()

        AudioWarpPort.warp(file_path,
          server: port_pid,
          output_path: output_path,
          tempo_factor: tempo_factor,
          pitch_semitones: pitch_semitones
        )
      catch
        :exit, reason ->
          {:error, "Port process crashed: #{inspect(reason)}"}
      end

    case result do
      {:ok, %{"output_path" => out_path, "duration" => duration}} ->
        # Store relative path
        relative_path = Path.relative_to(out_path, Storage.base_path())

        Logger.info("Audio warp complete: #{relative_path}, duration=#{duration}s")

        Phoenix.PubSub.broadcast(
          SoundForge.PubSub,
          "tracks:#{track_id}",
          {:warp_complete, track_id, %{
            file_path: relative_path,
            tempo_factor: tempo_factor,
            pitch_semitones: pitch_semitones,
            duration: duration
          }}
        )

        PipelineBroadcaster.broadcast_pipeline_complete(track_id)
        :ok

      {:error, reason} ->
        Logger.error("Audio warp failed: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end
end
