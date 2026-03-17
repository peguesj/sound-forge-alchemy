defmodule SoundForgeWeb.FileController do
  @moduledoc """
  Serves audio files from storage with path traversal protection.
  Also serves on-demand generated MIDI files from drum event analysis.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Audio.MidiExtractor
  alias SoundForge.Music
  alias SoundForge.Storage

  @doc """
  Generate and serve a MIDI file for a track's drum events.
  The .mid file is cached in /tmp/midi/ by track_id.
  """
  def serve_midi(conn, %{"track_id" => track_id}) do
    midi_path = Path.join(System.tmp_dir!(), "midi/#{track_id}.mid")
    File.mkdir_p!(Path.dirname(midi_path))

    case maybe_generate_midi(track_id, midi_path) do
      {:ok, path} ->
        conn
        |> put_resp_content_type("audio/midi")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{track_id}.mid"))
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> send_file(200, path)

      {:error, :no_drum_events} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "No drum events found for track"})

      {:error, reason} ->
        conn |> put_status(:internal_server_error) |> json(%{error: inspect(reason)})
    end
  end

  defp maybe_generate_midi(track_id, midi_path) do
    if File.exists?(midi_path) do
      {:ok, midi_path}
    else
      generate_midi(track_id, midi_path)
    end
  end

  defp generate_midi(track_id, midi_path) do
    with %{} = track <- Music.get_track(track_id),
         result when not is_nil(result) <- Music.get_analysis_result_for_track(track_id),
         drum_events when is_list(drum_events) and drum_events != [] <-
           Map.get(result, :result, %{}) |> Map.get("drum_events", []) do
      bpm = Map.get(result.result, "bpm") || track.bpm || 120.0
      MidiExtractor.extract(drum_events, bpm, midi_path)
    else
      nil -> {:error, :no_drum_events}
      [] -> {:error, :no_drum_events}
      _ -> {:error, :track_not_found}
    end
  end

  def serve(conn, %{"path" => path_parts}) do
    # Join path parts and sanitize
    file_path = Path.join(path_parts)

    # Decode any percent-encoded characters and check for traversal
    decoded = URI.decode(file_path)

    # Try resolving against known storage directories
    case resolve_to_allowed_path(decoded) do
      {:ok, full_path} -> serve_file(conn, full_path)
      :error -> conn |> put_status(:forbidden) |> json(%{error: "Forbidden"})
    end
  end

  defp resolve_to_allowed_path(decoded) do
    allowed_bases = [
      Storage.base_path(),
      Application.get_env(:sound_forge, :demucs_output_dir, "/tmp/demucs")
    ]

    # Build all candidate paths that pass the traversal check
    candidates =
      for base <- allowed_bases,
          full_path = Path.join(base, decoded) |> Path.expand(),
          expanded_base = Path.expand(base) <> "/",
          String.starts_with?(full_path, expanded_base),
          do: full_path

    # Prefer a path where the file actually exists
    case Enum.find(candidates, &File.exists?/1) do
      nil -> if candidates != [], do: {:ok, hd(candidates)}, else: :error
      path -> {:ok, path}
    end
  end

  defp serve_file(conn, path) do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        content_type = MIME.from_path(path)

        case get_req_header(conn, "range") do
          ["bytes=" <> range_spec] ->
            serve_range(conn, path, size, range_spec, content_type)

          _ ->
            conn
            |> put_resp_content_type(content_type)
            |> put_resp_header("accept-ranges", "bytes")
            |> put_resp_header("content-length", to_string(size))
            |> put_resp_header("cache-control", "public, max-age=86400, immutable")
            |> send_file(200, path)
        end

      {:error, _} ->
        conn |> put_status(:not_found) |> json(%{error: "File not found"})
    end
  end

  defp serve_range(conn, path, total_size, range_spec, content_type) do
    case parse_range(range_spec, total_size) do
      {:ok, {start_byte, end_byte}} ->
        length = end_byte - start_byte + 1

        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("accept-ranges", "bytes")
        |> put_resp_header("content-range", "bytes #{start_byte}-#{end_byte}/#{total_size}")
        |> put_resp_header("content-length", to_string(length))
        |> put_resp_header("cache-control", "public, max-age=86400, immutable")
        |> send_file(206, path, start_byte, length)

      :error ->
        conn
        |> put_resp_header("content-range", "bytes */#{total_size}")
        |> send_resp(416, "Range Not Satisfiable")
    end
  end

  defp parse_range(range_spec, total_size) do
    case String.split(range_spec, "-", parts: 2) do
      [start_str, ""] -> parse_open_range(start_str, total_size)
      [start_str, end_str] -> parse_bounded_range(start_str, end_str, total_size)
      _ -> :error
    end
  end

  defp parse_open_range(start_str, total_size) do
    with {start_byte, _} when start_byte >= 0 <- Integer.parse(start_str),
         true <- start_byte < total_size do
      {:ok, {start_byte, total_size - 1}}
    else
      _ -> :error
    end
  end

  defp parse_bounded_range(start_str, end_str, total_size) do
    with {start_byte, _} when start_byte >= 0 <- Integer.parse(start_str),
         {end_byte_raw, _} when end_byte_raw >= 0 <- Integer.parse(end_str) do
      end_byte = min(end_byte_raw, total_size - 1)
      if start_byte <= end_byte, do: {:ok, {start_byte, end_byte}}, else: :error
    else
      _ -> :error
    end
  end
end
