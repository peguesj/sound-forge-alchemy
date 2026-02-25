defmodule SoundForge.Sampler.PresetParser do
  @moduledoc """
  Parses hardware preset files and extracts pad/bank configuration data.

  Supports:
  - **TouchOSC** (.touchosc) -- ZIP archive containing `index.xml` with pad/fader/rotary layout
  - **Akai MPC X/Live/One** (.xpm) -- XML-based program files with pad assignments
  - **Akai MPC1000/2500 Legacy** (.pgm) -- Binary format with fixed-offset pad data

  All parsers return a normalized `{:ok, preset_data}` map or `{:error, reason}`.

  ## Preset Data Structure

      %{
        name: "Program Name",
        format: :touchosc | :mpc_xpm | :mpc_pgm,
        pads: [
          %{
            index: 0,
            label: "kick_01",
            sample_name: "kick_01.wav",
            midi_note: 36,
            volume: 1.0,         # 0.0..1.0
            pitch: 0.0,          # semitones
            pan: 0.5,            # 0.0..1.0 (center = 0.5)
            play_mode: :one_shot # :one_shot | :loop | :gate
          },
          ...
        ],
        midi_mappings: [
          %{
            midi_type: :note | :cc,
            midi_channel: 0,
            midi_number: 36,
            parameter_type: :pad_trigger | :pad_volume | :pad_pitch | :master_volume | :crossfader,
            parameter_index: 0
          },
          ...
        ]
      }
  """

  # -- TouchOSC Parsing --

  @doc """
  Parses a `.touchosc` file (ZIP containing `index.xml`).

  Extracts push controls as pad triggers, faders as volume/crossfader,
  rotaries as pitch/filter knobs, and generates MIDI mapping entries.

  ## Parameters
    - `binary` - raw file bytes

  ## Returns
    - `{:ok, preset_data}` on success
    - `{:error, reason}` on failure
  """
  @spec parse_touchosc(binary()) :: {:ok, map()} | {:error, String.t()}
  def parse_touchosc(binary) when is_binary(binary) do
    case :zip.unzip(binary, [:memory]) do
      {:ok, files} ->
        case find_index_xml(files) do
          {:ok, xml_content} ->
            charlist = :erlang.binary_to_list(xml_content)

            case :xmerl_scan.string(charlist, quiet: true) do
              {doc, _rest} ->
                preset = extract_touchosc_preset(doc)
                {:ok, preset}

              _ ->
                {:error, "Failed to parse TouchOSC index.xml"}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, "Failed to unzip TouchOSC file: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "TouchOSC parse error: #{Exception.message(e)}"}
  end

  # -- MPC XPM Parsing --

  @doc """
  Parses an Akai MPC `.xpm` program file (XML format).

  Extracts pad assignments from the `<Pads>` section including sample name,
  root note, level, tune, pan, play mode, and filter settings.

  ## Parameters
    - `binary` - raw file bytes (XML)

  ## Returns
    - `{:ok, preset_data}` on success
    - `{:error, reason}` on failure
  """
  @spec parse_mpc_xpm(binary()) :: {:ok, map()} | {:error, String.t()}
  def parse_mpc_xpm(binary) when is_binary(binary) do
    charlist = String.to_charlist(binary)

    case :xmerl_scan.string(charlist, quiet: true) do
      {doc, _rest} ->
        preset = extract_xpm_preset(doc)
        {:ok, preset}

      _ ->
        {:error, "Failed to parse MPC XPM XML"}
    end
  rescue
    e -> {:error, "MPC XPM parse error: #{Exception.message(e)}"}
  end

  # -- MPC PGM Parsing (Legacy Binary) --

  @doc """
  Parses an Akai MPC1000/2500 `.pgm` program file (binary format).

  The binary layout:
  - Bytes 0-3: Header/magic (skipped)
  - Byte 4: Pad count (or implicit 64)
  - Per pad (64 pads max), starting at offset 8, each entry ~24 bytes:
    - Bytes 0-15: Sample name (null-terminated ASCII)
    - Byte 16: Volume (0-127)
    - Byte 17: Pan (0-127, 64=center)
    - Byte 18: Tune (signed -12..+12)
    - Byte 19: Play mode (0=one_shot, 1=loop)
    - Byte 20: MIDI note (0-127)
    - Bytes 21-23: Reserved/padding

  ## Parameters
    - `binary` - raw file bytes

  ## Returns
    - `{:ok, preset_data}` on success
    - `{:error, reason}` on failure
  """
  @spec parse_mpc_pgm(binary()) :: {:ok, map()} | {:error, String.t()}
  def parse_mpc_pgm(binary) when is_binary(binary) do
    if byte_size(binary) < 8 do
      {:error, "PGM file too small (#{byte_size(binary)} bytes)"}
    else
      preset = extract_pgm_preset(binary)
      {:ok, preset}
    end
  rescue
    e -> {:error, "MPC PGM parse error: #{Exception.message(e)}"}
  end

  # -- Detect Format --

  @doc """
  Detects the preset format from a filename extension.

  Returns `:touchosc`, `:mpc_xpm`, `:mpc_pgm`, or `:unknown`.
  """
  @spec detect_format(String.t()) :: :touchosc | :mpc_xpm | :mpc_pgm | :unknown
  def detect_format(filename) when is_binary(filename) do
    ext = filename |> String.downcase() |> Path.extname()

    case ext do
      ".touchosc" -> :touchosc
      ".xpm" -> :mpc_xpm
      ".pgm" -> :mpc_pgm
      _ -> :unknown
    end
  end

  @doc """
  Parses a preset file, auto-detecting format from the filename.
  """
  @spec parse(binary(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(binary, filename) when is_binary(binary) and is_binary(filename) do
    case detect_format(filename) do
      :touchosc -> parse_touchosc(binary)
      :mpc_xpm -> parse_mpc_xpm(binary)
      :mpc_pgm -> parse_mpc_pgm(binary)
      :unknown -> {:error, "Unknown preset format: #{Path.extname(filename)}"}
    end
  end

  # ============================================================================
  # TouchOSC Internals
  # ============================================================================

  defp find_index_xml(files) do
    case Enum.find(files, fn {name, _content} ->
           name_str = to_string(name)
           String.ends_with?(name_str, "index.xml") or name_str == "index.xml"
         end) do
      {_name, content} when is_binary(content) -> {:ok, content}
      {_name, content} when is_list(content) -> {:ok, :erlang.list_to_binary(content)}
      nil -> {:error, "index.xml not found in TouchOSC archive"}
    end
  end

  defp extract_touchosc_preset(doc) do
    controls = find_elements(doc, :control)

    {pads, midi_mappings} =
      controls
      |> Enum.reduce({[], []}, fn control, {pads_acc, maps_acc} ->
        control_type = get_attribute(control, :type) || ""
        name = get_attribute(control, :name) || ""
        midi_type_str = get_attribute(control, :midi_type)
        midi_channel_str = get_attribute(control, :midi_channel)
        midi_number_str = get_attribute(control, :midi_number)

        midi_type = touchosc_midi_type(midi_type_str)
        midi_channel = parse_int(midi_channel_str, 0)
        midi_number = parse_int(midi_number_str, 0)

        case String.downcase(control_type) do
          "push" ->
            pad_index = length(pads_acc)

            if pad_index < 16 do
              pad = %{
                index: pad_index,
                label: name,
                sample_name: nil,
                midi_note: midi_number,
                volume: 1.0,
                pitch: 0.0,
                pan: 0.5,
                play_mode: :one_shot
              }

              mapping = %{
                midi_type: midi_type,
                midi_channel: midi_channel,
                midi_number: midi_number,
                parameter_type: :pad_trigger,
                parameter_index: pad_index
              }

              {pads_acc ++ [pad], maps_acc ++ [mapping]}
            else
              {pads_acc, maps_acc}
            end

          type when type in ["fader", "faderv", "faderh"] ->
            param_type = infer_fader_param(name)

            mapping = %{
              midi_type: midi_type,
              midi_channel: midi_channel,
              midi_number: midi_number,
              parameter_type: param_type,
              parameter_index: infer_parameter_index(name)
            }

            {pads_acc, maps_acc ++ [mapping]}

          type when type in ["rotary", "encoder"] ->
            param_type = infer_rotary_param(name)

            mapping = %{
              midi_type: midi_type,
              midi_channel: midi_channel,
              midi_number: midi_number,
              parameter_type: param_type,
              parameter_index: infer_parameter_index(name)
            }

            {pads_acc, maps_acc ++ [mapping]}

          "toggle" ->
            # Toggle controls -- map to pad trigger if appropriate
            {pads_acc, maps_acc}

          _ ->
            {pads_acc, maps_acc}
        end
      end)

    %{
      name: "TouchOSC Layout",
      format: :touchosc,
      pads: pads,
      midi_mappings: midi_mappings
    }
  end

  defp touchosc_midi_type("0"), do: :cc
  defp touchosc_midi_type("1"), do: :note
  defp touchosc_midi_type("2"), do: :program_change
  defp touchosc_midi_type(nil), do: :cc
  defp touchosc_midi_type(_), do: :cc

  defp infer_fader_param(name) do
    name_lower = String.downcase(name)

    cond do
      String.contains?(name_lower, "crossfader") or String.contains?(name_lower, "xfade") ->
        :crossfader

      String.contains?(name_lower, "master") ->
        :master_volume

      String.contains?(name_lower, "vol") ->
        :pad_volume

      true ->
        :pad_volume
    end
  end

  defp infer_rotary_param(name) do
    name_lower = String.downcase(name)

    cond do
      String.contains?(name_lower, "pitch") or String.contains?(name_lower, "tune") ->
        :pad_pitch

      String.contains?(name_lower, "filter") ->
        :pad_volume

      true ->
        :pad_pitch
    end
  end

  defp infer_parameter_index(name) do
    case Regex.run(~r/(\d+)/, name) do
      [_, n_str] ->
        n = String.to_integer(n_str)
        # Convert from 1-based to 0-based, clamped to 0..15
        max(0, min(15, n - 1))

      nil ->
        0
    end
  end

  # ============================================================================
  # MPC XPM Internals
  # ============================================================================

  defp extract_xpm_preset(doc) do
    pad_elements = find_elements(doc, :Pad)

    pads =
      pad_elements
      |> Enum.map(fn pad_elem ->
        number = get_attribute(pad_elem, :number) || get_child_text(pad_elem, :number)
        pad_index = parse_int(number, 0) |> min(63) |> max(0)

        sample_name = get_child_text(pad_elem, :SampleName) || ""
        root_note = parse_int(get_child_text(pad_elem, :RootNote), 36)
        level = parse_int(get_child_text(pad_elem, :Level), 100)
        tune = parse_int(get_child_text(pad_elem, :Tune), 0)
        pan = parse_int(get_child_text(pad_elem, :Pan), 50)
        play_mode_str = get_child_text(pad_elem, :PlayMode) || "ONE_SHOT"

        volume = min(level, 127) / 127.0
        pitch = min(max(tune, -24), 24) * 1.0
        pan_normalized = min(pan, 100) / 100.0
        play_mode = parse_play_mode(play_mode_str)

        label =
          if sample_name == "" do
            "Pad #{pad_index + 1}"
          else
            sample_name |> Path.basename() |> Path.rootname()
          end

        %{
          index: pad_index,
          label: label,
          sample_name: if(sample_name == "", do: nil, else: sample_name),
          midi_note: root_note,
          volume: Float.round(volume, 4),
          pitch: pitch,
          pan: Float.round(pan_normalized, 4),
          play_mode: play_mode
        }
      end)
      |> Enum.sort_by(& &1.index)
      |> Enum.take(16)

    midi_mappings =
      pads
      |> Enum.map(fn pad ->
        %{
          midi_type: :note,
          midi_channel: 0,
          midi_number: pad.midi_note,
          parameter_type: :pad_trigger,
          parameter_index: pad.index
        }
      end)

    # Try to extract program name
    name = get_child_text(doc, :ProgramName) || "MPC Program"

    %{
      name: name,
      format: :mpc_xpm,
      pads: pads,
      midi_mappings: midi_mappings
    }
  end

  defp parse_play_mode(str) when is_binary(str) do
    case String.upcase(str) do
      "ONE_SHOT" -> :one_shot
      "ONESHOT" -> :one_shot
      "ONE SHOT" -> :one_shot
      "LOOP" -> :loop
      "GATE" -> :gate
      _ -> :one_shot
    end
  end

  # ============================================================================
  # MPC PGM (Binary) Internals
  # ============================================================================

  @pgm_entry_size 24
  @pgm_header_size 8
  @pgm_sample_name_len 16

  defp extract_pgm_preset(binary) do
    # Skip header bytes, read pad entries
    data_section = binary_part(binary, @pgm_header_size, byte_size(binary) - @pgm_header_size)
    max_pads = min(64, div(byte_size(data_section), @pgm_entry_size))

    pads =
      for i <- 0..(max_pads - 1), reduce: [] do
        acc ->
          offset = i * @pgm_entry_size

          if offset + @pgm_entry_size <= byte_size(data_section) do
            entry = binary_part(data_section, offset, @pgm_entry_size)
            pad = parse_pgm_pad(entry, i)
            if pad, do: acc ++ [pad], else: acc
          else
            acc
          end
      end
      |> Enum.take(16)

    midi_mappings =
      pads
      |> Enum.map(fn pad ->
        %{
          midi_type: :note,
          midi_channel: 0,
          midi_number: pad.midi_note,
          parameter_type: :pad_trigger,
          parameter_index: pad.index
        }
      end)

    %{
      name: "MPC Legacy Program",
      format: :mpc_pgm,
      pads: pads,
      midi_mappings: midi_mappings
    }
  end

  defp parse_pgm_pad(entry, index) when byte_size(entry) >= @pgm_entry_size do
    <<
      sample_raw::binary-size(@pgm_sample_name_len),
      volume_byte::unsigned-8,
      pan_byte::unsigned-8,
      tune_byte::signed-8,
      play_mode_byte::unsigned-8,
      midi_note_byte::unsigned-8,
      _reserved::binary-size(3)
    >> = entry

    sample_name =
      sample_raw
      |> :binary.split(<<0>>)
      |> hd()
      |> String.trim()

    label =
      if sample_name == "" do
        "Pad #{index + 1}"
      else
        sample_name |> Path.rootname()
      end

    volume = min(volume_byte, 127) / 127.0
    pan = min(pan_byte, 127) / 127.0
    pitch = min(max(tune_byte, -24), 24) * 1.0
    midi_note = min(midi_note_byte, 127)
    play_mode = if play_mode_byte == 1, do: :loop, else: :one_shot

    %{
      index: index,
      label: label,
      sample_name: if(sample_name == "", do: nil, else: sample_name),
      midi_note: midi_note,
      volume: Float.round(volume, 4),
      pitch: pitch,
      pan: Float.round(pan, 4),
      play_mode: play_mode
    }
  end

  defp parse_pgm_pad(_, _), do: nil

  # ============================================================================
  # XML Helpers (using :xmerl)
  # ============================================================================

  defp find_elements({:xmlElement, name, _, _, _, _, _, _attrs, content, _, _, _} = elem, tag) do
    matches = if name == tag, do: [elem], else: []

    child_matches =
      content
      |> Enum.flat_map(fn child -> find_elements(child, tag) end)

    matches ++ child_matches
  end

  defp find_elements({:xmlDocument, _, _, _, content}, tag) do
    content
    |> Enum.flat_map(fn child -> find_elements(child, tag) end)
  end

  defp find_elements(_, _), do: []

  defp get_child_text(element, child_name) when is_atom(child_name) do
    case find_elements(element, child_name) do
      [{:xmlElement, _, _, _, _, _, _, _, content, _, _, _} | _] ->
        text =
          content
          |> Enum.filter(fn
            {:xmlText, _, _, _, _, _} -> true
            _ -> false
          end)
          |> Enum.map(fn {:xmlText, _, _, _, text, _} -> to_string(text) end)
          |> Enum.join()
          |> String.trim()

        if text == "", do: nil, else: text

      _ ->
        nil
    end
  end

  defp get_attribute({:xmlElement, _, _, _, _, _, _, attrs, _, _, _, _}, attr_name)
       when is_atom(attr_name) do
    case Enum.find(attrs, fn
           {:xmlAttribute, name, _, _, _, _, _, _, _, _} -> name == attr_name
           _ -> false
         end) do
      {:xmlAttribute, _, _, _, _, _, _, _, value, _} ->
        text = to_string(value) |> String.trim()
        if text == "", do: nil, else: text

      _ ->
        nil
    end
  end

  defp get_attribute(_, _), do: nil

  defp parse_int(nil, default), do: default

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(str, default) when is_list(str) do
    parse_int(to_string(str), default)
  end

  defp parse_int(_, default), do: default
end
