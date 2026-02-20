defmodule SoundForge.MIDI.Parser do
  @moduledoc """
  Decodes raw MIDI bytes into `%SoundForge.MIDI.Message{}` structs.

  Supports channel voice messages (note_on, note_off, cc, program_change),
  system exclusive (sysex), and system real-time messages (clock, start,
  stop, continue). Running status is supported for compact MIDI streams.
  """

  alias SoundForge.MIDI.Message

  @type parse_result :: {:ok, Message.t(), binary()} | {:error, atom()}

  # Status byte ranges
  @note_off 0x80
  @note_on 0x90
  @poly_pressure 0xA0
  @cc 0xB0
  @program_change 0xC0
  @channel_pressure 0xD0
  @pitch_bend 0xE0
  @sysex_start 0xF0
  @sysex_end 0xF7

  # System real-time
  @clock 0xF8
  @midi_start 0xFA
  @midi_continue 0xFB
  @midi_stop 0xFC

  @doc """
  Parses raw MIDI bytes into a list of `%MIDI.Message{}` structs.

  Accepts a binary of one or more MIDI messages. Returns a list of parsed
  messages. Malformed trailing bytes are silently dropped. Supports running
  status (subsequent data bytes reuse the last status byte).

  ## Examples

      iex> SoundForge.MIDI.Parser.parse(<<0x90, 60, 100>>)
      [%SoundForge.MIDI.Message{type: :note_on, channel: 0, data: %{note: 60, velocity: 100}}]

      iex> SoundForge.MIDI.Parser.parse(<<0xF8>>)
      [%SoundForge.MIDI.Message{type: :clock, channel: nil, data: %{}}]
  """
  @spec parse(binary()) :: [Message.t()]
  def parse(bytes) when is_binary(bytes) do
    now = System.monotonic_time(:microsecond)
    parse_stream(bytes, nil, now, [])
  end

  def parse(_), do: []

  # -- Stream parser with running status --

  defp parse_stream(<<>>, _status, _ts, acc), do: Enum.reverse(acc)

  # System real-time (single byte, can appear anywhere)
  defp parse_stream(<<@clock, rest::binary>>, status, ts, acc) do
    msg = %Message{type: :clock, channel: nil, timestamp: ts}
    parse_stream(rest, status, ts, [msg | acc])
  end

  defp parse_stream(<<@midi_start, rest::binary>>, status, ts, acc) do
    msg = %Message{type: :start, channel: nil, timestamp: ts}
    parse_stream(rest, status, ts, [msg | acc])
  end

  defp parse_stream(<<@midi_stop, rest::binary>>, status, ts, acc) do
    msg = %Message{type: :stop, channel: nil, timestamp: ts}
    parse_stream(rest, status, ts, [msg | acc])
  end

  defp parse_stream(<<@midi_continue, rest::binary>>, status, ts, acc) do
    msg = %Message{type: :continue, channel: nil, timestamp: ts}
    parse_stream(rest, status, ts, [msg | acc])
  end

  # SysEx
  defp parse_stream(<<@sysex_start, rest::binary>>, _status, ts, acc) do
    case parse_sysex(rest, <<>>) do
      {:ok, sysex_data, remaining} ->
        msg = %Message{type: :sysex, channel: nil, data: %{payload: sysex_data}, timestamp: ts}
        parse_stream(remaining, nil, ts, [msg | acc])

      :incomplete ->
        # Unterminated sysex, consume remaining bytes as payload
        msg = %Message{type: :sysex, channel: nil, data: %{payload: rest}, timestamp: ts}
        Enum.reverse([msg | acc])
    end
  end

  # Channel voice messages with status byte
  defp parse_stream(<<status_byte, rest::binary>>, _status, ts, acc)
       when status_byte >= 0x80 and status_byte <= 0xEF do
    parse_channel_message(status_byte, rest, ts, acc)
  end

  # Running status: data byte without a preceding status byte
  defp parse_stream(<<data_byte, rest::binary>>, status, ts, acc)
       when not is_nil(status) and data_byte < 0x80 do
    parse_channel_message(status, <<data_byte, rest::binary>>, ts, acc)
  end

  # Unknown or malformed byte, skip
  defp parse_stream(<<_byte, rest::binary>>, status, ts, acc) do
    parse_stream(rest, status, ts, acc)
  end

  # -- Channel message parsing --

  # Note Off: 3 bytes
  defp parse_channel_message(status, <<note, velocity, rest::binary>>, ts, acc)
       when status >= @note_off and status < @note_off + 16 do
    channel = status - @note_off

    msg = %Message{
      type: :note_off,
      channel: channel,
      data: %{note: note, velocity: velocity},
      timestamp: ts
    }

    parse_stream(rest, status, ts, [msg | acc])
  end

  # Note On: 3 bytes (velocity 0 = note_off)
  defp parse_channel_message(status, <<note, velocity, rest::binary>>, ts, acc)
       when status >= @note_on and status < @note_on + 16 do
    channel = status - @note_on

    type = if velocity == 0, do: :note_off, else: :note_on

    msg = %Message{
      type: type,
      channel: channel,
      data: %{note: note, velocity: velocity},
      timestamp: ts
    }

    parse_stream(rest, status, ts, [msg | acc])
  end

  # Polyphonic Pressure: 3 bytes
  defp parse_channel_message(status, <<note, pressure, rest::binary>>, ts, acc)
       when status >= @poly_pressure and status < @poly_pressure + 16 do
    channel = status - @poly_pressure

    msg = %Message{
      type: :poly_pressure,
      channel: channel,
      data: %{note: note, pressure: pressure},
      timestamp: ts
    }

    parse_stream(rest, status, ts, [msg | acc])
  end

  # Control Change: 3 bytes
  defp parse_channel_message(status, <<controller, value, rest::binary>>, ts, acc)
       when status >= @cc and status < @cc + 16 do
    channel = status - @cc

    msg = %Message{
      type: :cc,
      channel: channel,
      data: %{controller: controller, value: value},
      timestamp: ts
    }

    parse_stream(rest, status, ts, [msg | acc])
  end

  # Program Change: 2 bytes
  defp parse_channel_message(status, <<program, rest::binary>>, ts, acc)
       when status >= @program_change and status < @program_change + 16 do
    channel = status - @program_change

    msg = %Message{
      type: :program_change,
      channel: channel,
      data: %{program: program},
      timestamp: ts
    }

    parse_stream(rest, status, ts, [msg | acc])
  end

  # Channel Pressure: 2 bytes
  defp parse_channel_message(status, <<pressure, rest::binary>>, ts, acc)
       when status >= @channel_pressure and status < @channel_pressure + 16 do
    channel = status - @channel_pressure

    msg = %Message{
      type: :channel_pressure,
      channel: channel,
      data: %{pressure: pressure},
      timestamp: ts
    }

    parse_stream(rest, status, ts, [msg | acc])
  end

  # Pitch Bend: 3 bytes (14-bit value)
  defp parse_channel_message(status, <<lsb, msb, rest::binary>>, ts, acc)
       when status >= @pitch_bend and status < @pitch_bend + 16 do
    channel = status - @pitch_bend
    value = msb * 128 + lsb

    msg = %Message{
      type: :pitch_bend,
      channel: channel,
      data: %{value: value},
      timestamp: ts
    }

    parse_stream(rest, status, ts, [msg | acc])
  end

  # Incomplete message (not enough data bytes), drop remaining
  defp parse_channel_message(_status, _rest, _ts, acc) do
    Enum.reverse(acc)
  end

  # -- SysEx helpers --

  defp parse_sysex(<<@sysex_end, rest::binary>>, payload), do: {:ok, payload, rest}
  defp parse_sysex(<<byte, rest::binary>>, payload), do: parse_sysex(rest, <<payload::binary, byte>>)
  defp parse_sysex(<<>>, _payload), do: :incomplete
end
