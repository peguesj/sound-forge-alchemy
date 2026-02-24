defmodule SoundForge.DJ.Timecode do
  @moduledoc """
  SMPTE timecode conversion utilities.

  Converts deck playback position (milliseconds) to SMPTE timecode format
  (HH:MM:SS:FF) at 30 frames per second, the standard non-drop-frame rate
  used in NTSC video and many DAW/DJ applications.
  """

  @fps 30

  @doc """
  Convert milliseconds to SMPTE timecode string HH:MM:SS:FF at 30fps.

  ## Examples

      iex> SoundForge.DJ.Timecode.ms_to_smpte(0)
      "00:00:00:00"

      iex> SoundForge.DJ.Timecode.ms_to_smpte(1000)
      "00:00:01:00"

      iex> SoundForge.DJ.Timecode.ms_to_smpte(61_500)
      "00:01:01:15"

  """
  @spec ms_to_smpte(number()) :: String.t()
  def ms_to_smpte(ms) when is_number(ms) and ms >= 0 do
    total_frames = trunc(ms / 1000 * @fps)
    frames = rem(total_frames, @fps)
    total_seconds = div(total_frames, @fps)
    seconds = rem(total_seconds, 60)
    total_minutes = div(total_seconds, 60)
    minutes = rem(total_minutes, 60)
    hours = div(total_minutes, 60)

    pad2 = fn n -> String.pad_leading(to_string(n), 2, "0") end
    "#{pad2.(hours)}:#{pad2.(minutes)}:#{pad2.(seconds)}:#{pad2.(frames)}"
  end

  def ms_to_smpte(ms) when is_number(ms), do: "00:00:00:00"
  def ms_to_smpte(_), do: "00:00:00:00"

  @doc """
  Returns the configured frames-per-second rate.
  """
  @spec fps() :: pos_integer()
  def fps, do: @fps
end
