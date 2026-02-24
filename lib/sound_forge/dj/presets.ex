defmodule SoundForge.DJ.Presets do
  @moduledoc """
  Parser for DJ preset files -- Traktor .tsi and TouchOSC .touchosc formats.

  Extracts MIDI/OSC control mappings and converts them to
  `SoundForge.MIDI.Mapping` attribute maps ready for insertion.

  Uses OTP stdlib only: `:xmerl` for XML parsing, `:zip` for .touchosc archives.
  """

  @type mapping_attrs :: %{
          device_name: String.t(),
          midi_type: atom(),
          channel: non_neg_integer(),
          number: non_neg_integer(),
          action: atom(),
          params: map(),
          source: String.t()
        }

  # -- Traktor TSI Parsing --

  @traktor_control_map %{
    # Deck transport
    "deck.play" => {:dj_play, %{}},
    "deck.play_pause" => {:dj_play, %{}},
    "deck.cue" => {:dj_cue, %{"slot" => "1"}},
    "deck.cup" => {:dj_cue, %{"slot" => "1"}},
    # Tempo/pitch
    "deck.tempo_adjust" => {:dj_pitch, %{}},
    "deck.tempo_range" => {:dj_pitch, %{}},
    "deck.sync" => {:dj_pitch, %{}},
    # Crossfader
    "mixer.crossfader" => {:dj_crossfader, %{}},
    "mixer.xfader" => {:dj_crossfader, %{}},
    # Volume
    "deck.volume" => {:stem_volume, %{"target" => "master"}},
    "mixer.channel_fader" => {:stem_volume, %{"target" => "master"}},
    # Loop
    "deck.loop_active" => {:dj_loop_toggle, %{}},
    "deck.loop_in" => {:dj_loop_toggle, %{}},
    "deck.loop_out" => {:dj_loop_toggle, %{}},
    "deck.loop_size" => {:dj_loop_size, %{}},
    # Hot cues
    "deck.hotcue_1" => {:dj_cue, %{"slot" => "1"}},
    "deck.hotcue_2" => {:dj_cue, %{"slot" => "2"}},
    "deck.hotcue_3" => {:dj_cue, %{"slot" => "3"}},
    "deck.hotcue_4" => {:dj_cue, %{"slot" => "4"}},
    "deck.hotcue_5" => {:dj_cue, %{"slot" => "5"}},
    "deck.hotcue_6" => {:dj_cue, %{"slot" => "6"}},
    "deck.hotcue_7" => {:dj_cue, %{"slot" => "7"}},
    "deck.hotcue_8" => {:dj_cue, %{"slot" => "8"}}
  }

  @doc """
  Parses a Traktor .tsi file (XML) and returns mapping attributes.

  ## Parameters
    - `binary` - the raw file contents
    - `user_id` - the user to associate mappings with

  ## Returns
    - `{:ok, [mapping_attrs]}` on success
    - `{:error, reason}` on failure
  """
  @spec parse_tsi(binary(), binary()) :: {:ok, [mapping_attrs()]} | {:error, String.t()}
  def parse_tsi(binary, user_id) when is_binary(binary) and is_binary(user_id) do
    charlist = String.to_charlist(binary)

    case :xmerl_scan.string(charlist, quiet: true) do
      {doc, _rest} ->
        mappings = extract_tsi_mappings(doc, user_id)
        {:ok, mappings}

      _ ->
        {:error, "Failed to parse TSI XML"}
    end
  rescue
    e -> {:error, "TSI parse error: #{Exception.message(e)}"}
  end

  defp extract_tsi_mappings(doc, user_id) do
    # Find all Entry elements with Type="midi2control" or similar mapping entries
    entries = xpath_elements(doc, ~c"//Entry")

    entries
    |> Enum.flat_map(fn entry ->
      try do
        parse_tsi_entry(entry, user_id)
      rescue
        _ -> []
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_tsi_entry(entry, user_id) do
    # Extract the mapping attributes from a TSI Entry element
    # TSI entries typically contain MidiNote/Channel/ControlId
    midi_note = get_child_text(entry, ~c"MidiNote")
    channel = get_child_text(entry, ~c"Channel")
    control_id = get_child_text(entry, ~c"ControlId") || get_child_text(entry, ~c"Name")
    device_name = get_child_text(entry, ~c"DeviceName") || "Traktor Controller"
    type = get_child_text(entry, ~c"Type") || get_child_text(entry, ~c"MidiType")

    if midi_note && control_id do
      midi_number = parse_int(midi_note, 0) |> min(127) |> max(0)
      midi_channel = parse_int(channel, 0) |> min(15) |> max(0)

      # Determine deck number from control_id prefix or attribute
      deck_str = extract_deck(entry, control_id)

      # Normalize the control ID to match our lookup table
      normalized = normalize_traktor_control(control_id)

      case Map.get(@traktor_control_map, normalized) do
        {action, base_params} ->
          params = if deck_str, do: Map.put(base_params, "deck", deck_str), else: base_params

          midi_type =
            case String.downcase(to_string(type || "cc")) do
              t when t in ["note", "note_on"] -> :note_on
              "note_off" -> :note_off
              _ -> :cc
            end

          [
            %{
              user_id: user_id,
              device_name: to_string(device_name),
              midi_type: midi_type,
              channel: midi_channel,
              number: midi_number,
              action: action,
              params: params,
              source: "tsi"
            }
          ]

        nil ->
          # Unrecognized control -- skip silently
          []
      end
    else
      []
    end
  end

  defp normalize_traktor_control(control_id) when is_binary(control_id) do
    control_id
    |> String.downcase()
    |> String.replace(~r/^(deck_[a-d]|channel_[a-d])[._]/, "deck.")
    |> String.replace(~r/^(mixer)[._]/, "mixer.")
    |> String.replace(~r/_/, ".")
    |> String.replace(~r/\s+/, ".")
  end

  defp normalize_traktor_control(control_id) do
    to_string(control_id) |> normalize_traktor_control()
  end

  defp extract_deck(entry, control_id) do
    deck_attr = get_child_text(entry, ~c"Deck") || get_child_text(entry, ~c"Assignment")

    cond do
      deck_attr in ["A", "a", "0", "1"] -> "1"
      deck_attr in ["B", "b", "2", "3"] -> "2"
      String.contains?(String.downcase(to_string(control_id)), "deck_a") -> "1"
      String.contains?(String.downcase(to_string(control_id)), "deck_b") -> "2"
      true -> nil
    end
  end

  # -- TouchOSC Parsing --

  @touchosc_path_map %{
    # Deck transport
    "/deck/1/play" => {:dj_play, %{"deck" => "1"}},
    "/deck/2/play" => {:dj_play, %{"deck" => "2"}},
    "/deck/1/cue" => {:dj_cue, %{"deck" => "1", "slot" => "1"}},
    "/deck/2/cue" => {:dj_cue, %{"deck" => "2", "slot" => "1"}},
    # Volume / faders
    "/deck/1/volume" => {:stem_volume, %{"deck" => "1", "target" => "master"}},
    "/deck/2/volume" => {:stem_volume, %{"deck" => "2", "target" => "master"}},
    "/mixer/crossfader" => {:dj_crossfader, %{}},
    "/crossfader" => {:dj_crossfader, %{}},
    # Stems
    "/stem/1/volume" => {:stem_volume, %{"target" => "vocals"}},
    "/stem/2/volume" => {:stem_volume, %{"target" => "drums"}},
    "/stem/3/volume" => {:stem_volume, %{"target" => "bass"}},
    "/stem/4/volume" => {:stem_volume, %{"target" => "other"}},
    "/stem/1/mute" => {:stem_mute, %{"target" => "vocals"}},
    "/stem/2/mute" => {:stem_mute, %{"target" => "drums"}},
    "/stem/3/mute" => {:stem_mute, %{"target" => "bass"}},
    "/stem/4/mute" => {:stem_mute, %{"target" => "other"}},
    # Pitch / tempo
    "/deck/1/pitch" => {:dj_pitch, %{"deck" => "1"}},
    "/deck/2/pitch" => {:dj_pitch, %{"deck" => "2"}},
    # Loops
    "/deck/1/loop" => {:dj_loop_toggle, %{"deck" => "1"}},
    "/deck/2/loop" => {:dj_loop_toggle, %{"deck" => "2"}},
    # Transport
    "/play" => {:play, %{}},
    "/stop" => {:stop, %{}}
  }

  @doc """
  Parses a TouchOSC .touchosc file (ZIP containing index.xml) and returns mapping attributes.

  ## Parameters
    - `binary` - the raw file contents
    - `user_id` - the user to associate mappings with

  ## Returns
    - `{:ok, [mapping_attrs]}` on success
    - `{:error, reason}` on failure
  """
  @spec parse_touchosc(binary(), binary()) :: {:ok, [mapping_attrs()]} | {:error, String.t()}
  def parse_touchosc(binary, user_id) when is_binary(binary) and is_binary(user_id) do
    case :zip.unzip(binary, [:memory]) do
      {:ok, files} ->
        # Find index.xml in the zip contents
        case find_index_xml(files) do
          {:ok, xml_content} ->
            charlist = :erlang.binary_to_list(xml_content)

            case :xmerl_scan.string(charlist, quiet: true) do
              {doc, _rest} ->
                mappings = extract_touchosc_mappings(doc, user_id)
                {:ok, mappings}

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

  defp find_index_xml(files) do
    case Enum.find(files, fn {name, _content} ->
           name_str = to_string(name)
           String.ends_with?(name_str, "index.xml") or name_str == ~c"index.xml"
         end) do
      {_name, content} when is_binary(content) -> {:ok, content}
      {_name, content} when is_list(content) -> {:ok, :erlang.list_to_binary(content)}
      nil -> {:error, "index.xml not found in TouchOSC archive"}
    end
  end

  defp extract_touchosc_mappings(doc, user_id) do
    # TouchOSC controls are nested <control> elements with osc_cs attributes
    controls = xpath_elements(doc, ~c"//control")

    controls
    |> Enum.flat_map(fn control ->
      try do
        parse_touchosc_control(control, user_id)
      rescue
        _ -> []
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_touchosc_control(control, user_id) do
    osc_path = get_attribute(control, ~c"osc_cs") || get_child_text(control, ~c"osc_cs")
    control_type = get_attribute(control, ~c"type") || ""

    if osc_path && osc_path != "" do
      path_str = to_string(osc_path)

      # Try exact match first, then prefix match
      case Map.get(@touchosc_path_map, path_str) || match_path_pattern(path_str) do
        {action, params} ->
          # Generate a pseudo MIDI mapping from the OSC path
          # Use a hash of the path for deterministic channel/number
          hash = :erlang.phash2(path_str, 16384)
          channel = rem(hash, 16)
          number = rem(div(hash, 16), 128)

          [
            %{
              user_id: user_id,
              device_name: "TouchOSC",
              midi_type: :cc,
              channel: channel,
              number: number,
              action: action,
              params: Map.put(params, "osc_path", path_str),
              source: "touchosc"
            }
          ]

        nil ->
          # Check if it looks like a known pattern
          case infer_action_from_osc_path(path_str) do
            {action, params} ->
              hash = :erlang.phash2(path_str, 16384)
              channel = rem(hash, 16)
              number = rem(div(hash, 16), 128)

              [
                %{
                  user_id: user_id,
                  device_name: "TouchOSC #{control_type}",
                  midi_type: :cc,
                  channel: channel,
                  number: number,
                  action: action,
                  params: Map.put(params, "osc_path", path_str),
                  source: "touchosc"
                }
              ]

            nil ->
              []
          end
      end
    else
      []
    end
  end

  defp match_path_pattern(path) do
    cond do
      Regex.match?(~r{^/stem/\d+/volume$}, path) ->
        [_, n] = Regex.run(~r{/stem/(\d+)/volume}, path)
        {:stem_volume, %{"target" => stem_name(n)}}

      Regex.match?(~r{^/stem/\d+/mute$}, path) ->
        [_, n] = Regex.run(~r{/stem/(\d+)/mute}, path)
        {:stem_mute, %{"target" => stem_name(n)}}

      Regex.match?(~r{^/deck/\d+/play$}, path) ->
        [_, n] = Regex.run(~r{/deck/(\d+)/play}, path)
        {:dj_play, %{"deck" => n}}

      Regex.match?(~r{^/deck/\d+/pitch$}, path) ->
        [_, n] = Regex.run(~r{/deck/(\d+)/pitch}, path)
        {:dj_pitch, %{"deck" => n}}

      true ->
        nil
    end
  end

  defp infer_action_from_osc_path(path) do
    path_lower = String.downcase(path)

    cond do
      String.contains?(path_lower, "crossfader") or String.contains?(path_lower, "xfader") ->
        {:dj_crossfader, %{}}

      String.contains?(path_lower, "play") ->
        {:play, %{}}

      String.contains?(path_lower, "stop") ->
        {:stop, %{}}

      String.contains?(path_lower, "volume") or String.contains?(path_lower, "fader") ->
        {:stem_volume, %{"target" => "master"}}

      true ->
        nil
    end
  end

  defp stem_name("1"), do: "vocals"
  defp stem_name("2"), do: "drums"
  defp stem_name("3"), do: "bass"
  defp stem_name("4"), do: "other"
  defp stem_name("5"), do: "guitar"
  defp stem_name("6"), do: "piano"
  defp stem_name(n), do: "stem_#{n}"

  # -- XML Helpers --

  # Extract all elements matching an XPath-like selector (simple descendant search)
  defp xpath_elements(doc, tag_name) do
    tag_atom =
      case tag_name do
        name when is_list(name) -> List.to_atom(name)
        name when is_atom(name) -> name
      end

    find_elements(doc, tag_atom)
  end

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

  defp get_child_text(element, child_name) do
    child_atom =
      case child_name do
        name when is_list(name) -> List.to_atom(name)
        name when is_atom(name) -> name
      end

    case find_elements(element, child_atom) do
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

  defp get_attribute({:xmlElement, _, _, _, _, _, _, attrs, _, _, _, _}, attr_name) do
    attr_atom =
      case attr_name do
        name when is_list(name) -> List.to_atom(name)
        name when is_atom(name) -> name
      end

    case Enum.find(attrs, fn
           {:xmlAttribute, name, _, _, _, _, _, _, _, _} -> name == attr_atom
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
