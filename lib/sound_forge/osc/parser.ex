defmodule SoundForge.OSC.Parser do
  @moduledoc "Minimal OSC 1.0 message encoder/decoder."

  @type osc_message :: %{address: String.t(), args: [term()]}

  @spec decode(binary()) :: {:ok, [osc_message()]} | {:error, term()}
  def decode(<<"#bundle\0", _timetag::binary-size(8), rest::binary>>) do
    case decode_bundle_elements(rest, []) do
      {:ok, messages} -> {:ok, messages}
      error -> error
    end
  end

  def decode(data) when is_binary(data) do
    case decode_message(data) do
      {:ok, msg} -> {:ok, [msg]}
      error -> error
    end
  end

  @spec encode(String.t(), [term()]) :: binary()
  def encode(address, args \\ []) do
    addr_padded = pad_string(address)
    type_tag = "," <> Enum.map_join(args, "", &type_tag_for/1)
    type_padded = pad_string(type_tag)
    args_encoded = Enum.map(args, &encode_arg/1) |> IO.iodata_to_binary()
    addr_padded <> type_padded <> args_encoded
  end

  # -- Private --

  defp decode_message(data) do
    with {:ok, address, rest} <- read_string(data),
         {:ok, type_tag, rest} <- read_string(rest),
         {:ok, args} <- decode_args(String.graphemes(String.trim_leading(type_tag, ",")), rest) do
      {:ok, %{address: address, args: args}}
    end
  end

  defp decode_bundle_elements(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_bundle_elements(<<size::32, element::binary-size(size), rest::binary>>, acc) do
    case decode(element) do
      {:ok, msgs} -> decode_bundle_elements(rest, msgs ++ acc)
      error -> error
    end
  end

  defp decode_bundle_elements(_, _), do: {:error, :invalid_bundle}

  defp decode_args([], _rest), do: {:ok, []}

  defp decode_args(tags, data) do
    decode_args(tags, data, [])
  end

  defp decode_args([], _data, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_args(["f" | rest], <<value::float-32, data::binary>>, acc) do
    decode_args(rest, data, [value | acc])
  end

  defp decode_args(["i" | rest], <<value::signed-integer-32, data::binary>>, acc) do
    decode_args(rest, data, [value | acc])
  end

  defp decode_args(["s" | rest], data, acc) do
    case read_string(data) do
      {:ok, str, remaining} -> decode_args(rest, remaining, [str | acc])
      error -> error
    end
  end

  defp decode_args(["b" | rest], <<size::32, blob::binary-size(size), padding::binary>>, acc) do
    pad_size = pad_amount(size)

    <<_::binary-size(pad_size), remaining::binary>> = padding
    decode_args(rest, remaining, [blob | acc])
  rescue
    _ -> {:error, :invalid_blob}
  end

  defp decode_args([_tag | rest], data, acc) do
    # Skip unknown type tags
    decode_args(rest, data, acc)
  end

  defp read_string(data) do
    case :binary.split(data, <<0>>) do
      [str, rest] ->
        total = byte_size(str) + 1
        pad = pad_amount(total)

        case rest do
          <<_::binary-size(pad), remaining::binary>> -> {:ok, str, remaining}
          _ -> {:ok, str, rest}
        end

      _ ->
        {:error, :invalid_string}
    end
  end

  defp pad_string(str) do
    data = str <> <<0>>
    pad = pad_amount(byte_size(data))
    data <> :binary.copy(<<0>>, pad)
  end

  defp pad_amount(size), do: rem(4 - rem(size, 4), 4)

  defp type_tag_for(v) when is_float(v), do: "f"
  defp type_tag_for(v) when is_integer(v), do: "i"
  defp type_tag_for(v) when is_binary(v), do: "s"

  defp encode_arg(v) when is_float(v), do: <<v::float-32>>
  defp encode_arg(v) when is_integer(v), do: <<v::signed-integer-32>>
  defp encode_arg(v) when is_binary(v), do: pad_string(v)
end
