defmodule SoundForge.DJ.Layouts.Rekordbox do
  @moduledoc """
  Parser for Pioneer Rekordbox XML exports (`rekordbox.xml`).

  Rekordbox can export its entire library as an XML file via
  File → Export Collection in xml format. This module parses that export
  to extract track metadata, hot cue points, memory cues, beat grid tempos,
  and playlists.

  ## Usage

      binary = File.read!("rekordbox.xml")
      {:ok, %{tracks: tracks, playlists: playlists}} = Rekordbox.parse(binary)

  ## Cue Type Mapping

  | Rekordbox Type | Atom            |
  |---------------|-----------------|
  | 0             | :hot_cue        |
  | 1             | :fade_in        |
  | 2             | :fade_out       |
  | 3             | :load           |
  | 4             | :loop           |
  | -1            | :memory_cue     |

  ## Position Units

  Rekordbox stores positions in seconds as floating-point strings.
  This parser converts them to milliseconds (integer).
  """

  require Logger

  @cue_type_map %{
    "0" => :hot_cue,
    "1" => :fade_in,
    "2" => :fade_out,
    "3" => :load,
    "4" => :loop,
    "-1" => :memory_cue
  }

  @doc """
  Parse a Rekordbox XML binary.

  Returns `{:ok, %{tracks: [track_map], playlists: [playlist_map]}}` on success,
  or `{:error, reason}` on failure.
  """
  @spec parse(binary()) :: {:ok, %{tracks: list(), playlists: list()}} | {:error, term()}
  def parse(binary) when is_binary(binary) do
    case :xmerl_scan.string(String.to_charlist(binary), [{:quiet, true}]) do
      {xml_doc, _rest} ->
        tracks = extract_tracks(xml_doc)
        playlists = extract_playlists(xml_doc)
        {:ok, %{tracks: tracks, playlists: playlists}}

      {:error, reason} ->
        {:error, {:xml_parse_error, reason}}
    end
  rescue
    e -> {:error, {:parse_exception, Exception.message(e)}}
  end

  # ---------------------------------------------------------------------------
  # Track extraction
  # ---------------------------------------------------------------------------

  defp extract_tracks(xml_doc) do
    collection_nodes = xpath(xml_doc, "//COLLECTION/TRACK")

    Enum.map(collection_nodes, fn track_node ->
      cue_points = extract_cue_points(track_node)
      tempos = extract_tempos(track_node)

      %{
        track_id: attr(track_node, "TrackID"),
        name: attr(track_node, "Name"),
        artist: attr(track_node, "Artist"),
        album: attr(track_node, "Album"),
        genre: attr(track_node, "Genre"),
        total_time_seconds: parse_float(attr(track_node, "TotalTime")),
        average_bpm: parse_float(attr(track_node, "AverageBpm")),
        tonality: attr(track_node, "Tonality"),
        location: attr(track_node, "Location"),
        date_added: attr(track_node, "DateAdded"),
        cue_points: cue_points,
        tempos: tempos
      }
    end)
  end

  defp extract_cue_points(track_node) do
    track_node
    |> child_elements("POSITION_MARK")
    |> Enum.map(fn node ->
      type_str = attr(node, "Type")

      %{
        name: attr(node, "Name"),
        type_atom: Map.get(@cue_type_map, type_str, :unknown),
        type_raw: type_str,
        start_ms: seconds_to_ms(attr(node, "Start")),
        end_ms: seconds_to_ms(attr(node, "End")),
        num: parse_int(attr(node, "Num"))
      }
    end)
  end

  defp extract_tempos(track_node) do
    track_node
    |> child_elements("TEMPO")
    |> Enum.map(fn node ->
      %{
        start_ms: seconds_to_ms(attr(node, "Inizio")),
        bpm: parse_float(attr(node, "Bpm")),
        time_signature: attr(node, "Metro"),
        beat_number: parse_int(attr(node, "Battito"))
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Playlist extraction
  # ---------------------------------------------------------------------------

  defp extract_playlists(xml_doc) do
    root_nodes = xpath(xml_doc, "//PLAYLISTS/NODE")
    Enum.flat_map(root_nodes, &extract_playlist_node/1)
  end

  defp extract_playlist_node(node) do
    name = attr(node, "Name")
    type = attr(node, "Type")

    case type do
      "1" ->
        # Playlist node with tracks
        track_ids =
          node
          |> child_elements("TRACK")
          |> Enum.map(fn t -> attr(t, "Key") end)
          |> Enum.reject(&is_nil/1)

        [%{name: name, type: :playlist, track_ids: track_ids}]

      "0" ->
        # Folder node — recurse into children
        children =
          node
          |> child_elements("NODE")
          |> Enum.flat_map(&extract_playlist_node/1)

        [%{name: name, type: :folder, track_ids: [], children: children}]

      _ ->
        []
    end
  end

  # ---------------------------------------------------------------------------
  # XPath / XML helpers
  # ---------------------------------------------------------------------------

  defp xpath(doc, path) do
    path_chars = String.to_charlist(path)

    try do
      :xmerl_xpath.string(path_chars, doc)
    rescue
      _ -> []
    end
  end

  defp child_elements(node, tag) do
    tag_atom = String.to_atom(tag)

    node
    |> :xmerl_lib.content(node)
    |> List.flatten()
    |> Enum.filter(fn
      {:xmlElement, ^tag_atom, _, _, _, _, _, _, _, _, _, _} -> true
      _ -> false
    end)
  rescue
    _ -> []
  end

  defp attr(node, name) do
    name_atom = String.to_atom(name)

    try do
      attrs = :xmerl_lib.get_attribute_value(name_atom, node, nil)

      case attrs do
        nil -> nil
        val when is_list(val) -> List.to_string(val)
        val -> to_string(val)
      end
    rescue
      _ ->
        # Fallback: manually scan attribute list
        case node do
          {:xmlElement, _, _, _, _, _, _, attr_list, _, _, _, _} ->
            Enum.find_value(attr_list, nil, fn
              {:xmlAttribute, ^name_atom, _, _, _, _, _, _, val, _} ->
                if is_list(val), do: List.to_string(val), else: to_string(val)

              _ ->
                nil
            end)

          _ ->
            nil
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Type coercions
  # ---------------------------------------------------------------------------

  defp seconds_to_ms(nil), do: nil
  defp seconds_to_ms(""), do: nil

  defp seconds_to_ms(str) do
    case Float.parse(str) do
      {f, _} -> round(f * 1000)
      :error -> nil
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) do
    case Integer.parse(str) do
      {i, _} -> i
      :error -> nil
    end
  end
end
