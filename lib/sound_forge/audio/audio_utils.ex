defmodule SoundForge.Audio.AudioUtils do
  @moduledoc """
  Utility functions for audio file manipulation using ffmpeg.
  """

  require Logger

  @default_preview_duration 60

  @doc """
  Truncates an audio file to a preview duration (default 60 seconds).

  Uses ffmpeg with stream copy for speed. Returns `{:ok, preview_path}`
  or `{:error, reason}`.

  ## Options

    * `:duration` - Preview duration in seconds (default: #{@default_preview_duration})
  """
  @spec truncate_to_preview(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def truncate_to_preview(file_path, opts \\ []) do
    duration = Keyword.get(opts, :duration, @default_preview_duration)
    ext = Path.extname(file_path)
    base = String.replace_suffix(file_path, ext, "")
    preview_path = "#{base}_preview#{ext}"

    args = [
      "-y",
      "-i", file_path,
      "-t", to_string(duration),
      "-c", "copy",
      "-loglevel", "error",
      preview_path
    ]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, preview_path}

      {output, exit_code} ->
        Logger.error("ffmpeg truncation failed (exit #{exit_code}): #{output}")
        {:error, "ffmpeg failed with exit code #{exit_code}"}
    end
  rescue
    e in ErlangError ->
      {:error, "ffmpeg not available: #{inspect(e)}"}
  end
end
