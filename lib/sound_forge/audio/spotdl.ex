defmodule SoundForge.Audio.SpotDL do
  @moduledoc """
  Wrapper for Spotify metadata extraction and audio downloading.

  Uses a custom Python helper (priv/python/spotify_dl.py) that calls spotipy
  for metadata and yt-dlp for audio downloading. This replaces the spotdl CLI
  which hangs due to Spotify's deprecated audio_features endpoint.
  """

  require Logger

  @metadata_timeout 60_000
  @download_timeout 300_000

  @doc """
  Fetches metadata for a Spotify URL.

  Returns a list of track metadata maps for the given URL, whether it's a
  single track, album, or playlist. Each map contains fields like:
  - `"name"` - track title
  - `"artists"` - list of artist names
  - `"album_name"` - album name
  - `"album_artist"` - album artist
  - `"duration"` - duration in seconds
  - `"song_id"` - Spotify track ID
  - `"cover_url"` - album art URL
  - `"url"` - Spotify URL for the track

  ## Examples

      iex> SpotDL.fetch_metadata("https://open.spotify.com/track/abc123")
      {:ok, [%{"name" => "Song Title", "artists" => ["Artist"], ...}]}

      iex> SpotDL.fetch_metadata("https://open.spotify.com/album/xyz")
      {:ok, [%{"name" => "Track 1", ...}, %{"name" => "Track 2", ...}]}
  """
  @spec fetch_metadata(String.t()) :: {:ok, list(map())} | {:error, String.t()}
  def fetch_metadata(url) when is_binary(url) do
    Logger.metadata(spotdl_cmd: "metadata")
    Logger.info("Fetching metadata for #{url}")

    unless credentials_configured?() do
      Logger.error("Spotify API credentials not configured")

      {:error,
       "Spotify API credentials not configured. Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET."}
    else
      case run_helper(["metadata", url], @metadata_timeout) do
        {:ok, output, _stderr} ->
          parse_json_output(output)

        {:error, :timeout} ->
          Logger.error("Metadata fetch timed out after #{div(@metadata_timeout, 1000)}s")
          {:error, "Metadata fetch timed out. Spotify may be rate-limiting requests."}

        {:error, reason} ->
          Logger.error("Metadata fetch failed: #{reason}")
          {:error, "Failed to fetch metadata: #{reason}"}
      end
    end
  end

  defp credentials_configured? do
    config = Application.get_env(:sound_forge, :spotify, [])
    client_id = Keyword.get(config, :client_id)
    client_secret = Keyword.get(config, :client_secret)
    is_binary(client_id) and client_id != "" and is_binary(client_secret) and client_secret != ""
  end

  @doc """
  Downloads a track from a Spotify URL.

  Returns the path to the downloaded file on success.

  ## Options

    * `:output_dir` - directory to save downloaded files (default: "priv/uploads/downloads")
    * `:format` - audio format (default: "mp3")
    * `:bitrate` - audio bitrate (default: "320k")
    * `:output_template` - filename template (default: "{track-id}")
  """
  @spec download(String.t(), keyword()) ::
          {:ok, %{path: String.t(), size: integer()}} | {:error, String.t()}
  def download(url, opts \\ []) when is_binary(url) do
    output_dir = Keyword.get(opts, :output_dir, default_downloads_dir()) |> Path.expand()
    format = Keyword.get(opts, :format, "mp3")
    bitrate = Keyword.get(opts, :bitrate, "320k")
    output_template = Keyword.get(opts, :output_template, "{track-id}")

    File.mkdir_p!(output_dir)

    args = [
      "download",
      url,
      "--output-dir",
      output_dir,
      "--output-template",
      output_template,
      "--format",
      format,
      "--bitrate",
      bitrate
    ]

    Logger.metadata(spotdl_cmd: "download")
    Logger.info("Starting download for #{url}")

    case run_helper(args, @download_timeout) do
      {:ok, output, _stderr} ->
        parse_download_result(output)

      {:error, :timeout} ->
        Logger.error("Download timed out after #{div(@download_timeout, 1000)}s")
        {:error, "Download timed out. Spotify may be rate-limiting requests."}

      {:error, reason} ->
        Logger.error("Download failed: #{reason}")
        {:error, "Download failed: #{reason}"}
    end
  end

  @doc """
  Downloads a track by searching YouTube directly with the provided metadata.

  Bypasses the Spotify API entirely -- useful as a fallback when Spotify is
  unavailable but the track's metadata is already stored in the database.

  ## Options

  Same as `download/2`.
  """
  @spec download_direct(map(), keyword()) ::
          {:ok, %{path: String.t(), size: integer()}} | {:error, String.t()}
  def download_direct(metadata, opts \\ []) do
    title = Map.get(metadata, :title) || Map.get(metadata, "title")
    artist = Map.get(metadata, :artist) || Map.get(metadata, "artist")
    duration = Map.get(metadata, :duration) || Map.get(metadata, "duration")

    if is_nil(title) or title == "" or is_nil(artist) or artist == "" do
      {:error, "Cannot search YouTube without title and artist"}
    else
      output_dir = Keyword.get(opts, :output_dir, default_downloads_dir()) |> Path.expand()
      format = Keyword.get(opts, :format, "mp3")
      bitrate = Keyword.get(opts, :bitrate, "320k")
      output_template = Keyword.get(opts, :output_template, "direct")

      File.mkdir_p!(output_dir)

      args =
        [
          "download-direct",
          "--title",
          to_string(title),
          "--artist",
          to_string(artist),
          "--output-dir",
          output_dir,
          "--output-template",
          output_template,
          "--format",
          format,
          "--bitrate",
          bitrate
        ] ++
          if(duration, do: ["--duration", to_string(duration)], else: [])

      Logger.metadata(spotdl_cmd: "download-direct")
      Logger.info("Starting direct download (no Spotify API): \"#{title}\" by #{artist}")

      case run_helper(args, @download_timeout) do
        {:ok, output, _stderr} ->
          parse_download_result(output)

        {:error, :timeout} ->
          Logger.error("Direct download timed out after #{div(@download_timeout, 1000)}s")
          {:error, "Direct download timed out"}

        {:error, reason} ->
          Logger.error("Direct download failed: #{reason}")
          {:error, "Direct download failed: #{reason}"}
      end
    end
  end

  @doc """
  Checks if the helper script and its dependencies are available.
  """
  @spec available?() :: boolean()
  def available? do
    python = System.find_executable(python_cmd())
    script = helper_script_path()
    is_binary(python) and File.exists?(script)
  end

  # -- Private --

  # Parse the download result from the helper's stdout.
  # The result JSON ({"path": ..., "size": ...}) is emitted as the last line,
  # but yt-dlp/ffmpeg noise may leak through despite filtering. We scan all
  # lines for a valid result object rather than parsing the blob wholesale.
  defp parse_download_result(output) do
    result =
      output
      |> String.split("\n")
      |> Enum.reverse()
      |> Enum.find_value(fn line ->
        case Jason.decode(String.trim(line)) do
          {:ok, %{"path" => path, "size" => size}} -> {:ok, %{path: path, size: size}}
          _ -> nil
        end
      end)

    case result do
      {:ok, _} = success ->
        success

      nil ->
        raw_snippet = String.slice(output, 0, 200)
        raw_truncated = String.slice(output, 0, 2000)

        Logger.warning(
          "Failed to parse download result. Raw output (#{byte_size(output)} bytes):\n#{raw_truncated}"
        )

        {:error, "Failed to parse download result: #{raw_snippet}"}
    end
  end

  defp run_helper(args, timeout) do
    python = System.find_executable(python_cmd())
    script = helper_script_path()

    unless python, do: raise(%ErlangError{original: :enoent})
    unless File.exists?(script), do: raise(%ErlangError{original: :enoent})

    full_args = [script | args]

    port =
      Port.open({:spawn_executable, python}, [
        :binary,
        :exit_status,
        {:args, full_args},
        {:env, spotify_env()},
        :stderr_to_stdout
      ])

    collect_output(port, "", timeout)
  rescue
    e in ErlangError ->
      {:error, "Helper not available: #{inspect(e)}"}
  end

  defp collect_output(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        Logger.debug("SpotDL port data chunk: #{byte_size(data)} bytes")
        collect_output(port, acc <> data, timeout)

      {^port, {:exit_status, 0}} ->
        Logger.debug("SpotDL raw output before split (#{byte_size(acc)} bytes):\n#{String.slice(acc, 0, 2000)}")
        # Split stdout JSON (last line) from stderr status messages
        lines = String.split(String.trim(acc), "\n")
        {stderr_lines, stdout_lines} = Enum.split_with(lines, &status_line?/1)
        stdout = Enum.join(stdout_lines, "\n")
        stderr = Enum.join(stderr_lines, "\n")
        {:ok, stdout, stderr}

      {^port, {:exit_status, code}} ->
        # Try to extract error from output
        error_msg = extract_error(acc) || "Process exited with code #{code}"
        {:error, error_msg}
    after
      timeout ->
        kill_port(port)
        {:error, :timeout}
    end
  end

  defp status_line?(line) do
    case Jason.decode(line) do
      {:ok, %{"status" => _}} -> true
      {:ok, %{"error" => _}} -> true
      _ -> noise_line?(line)
    end
  end

  # yt-dlp and ffmpeg emit various bracketed prefixes beyond just [download]
  @noise_prefixes ~w([download] [ExtractAudio] [ffmpeg] [youtube] [yt-dlp] [info] [generic] [debug] WARNING: ERROR:)

  # Matches percentage progress lines like "  5.2%" or "100%"
  @progress_re ~r/^\d+\.?\d*%/

  defp noise_line?(line) do
    trimmed = String.trim(line)

    trimmed == "" or
      Enum.any?(@noise_prefixes, &String.starts_with?(trimmed, &1)) or
      Regex.match?(@progress_re, trimmed)
  end

  defp extract_error(output) do
    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Jason.decode(line) do
        {:ok, %{"error" => msg}} -> msg
        _ -> nil
      end
    end)
  end

  defp kill_port(port) do
    case :erlang.port_info(port, :os_pid) do
      {:os_pid, os_pid} ->
        Port.close(port)
        System.cmd("kill", ["-9", to_string(os_pid)], stderr_to_stdout: true)

      _ ->
        Port.close(port)
    end
  catch
    _, _ -> :ok
  end

  defp parse_json_output(output) do
    output = String.trim(output)

    case Jason.decode(output) do
      {:ok, [_ | _] = tracks} ->
        {:ok, tracks}

      {:ok, []} ->
        {:error, "No tracks found for this URL"}

      # Playlist format: {"playlist": {...}, "tracks": [...]}
      {:ok, %{"playlist" => playlist, "tracks" => [_ | _] = tracks}} ->
        {:ok, tracks, playlist}

      {:ok, %{"playlist" => _playlist, "tracks" => []}} ->
        {:error, "No tracks found for this URL"}

      {:ok, _} ->
        {:error, "Unexpected response format"}

      {:error, _} ->
        {:error, "Failed to parse output"}
    end
  end

  defp spotify_env do
    config = Application.get_env(:sound_forge, :spotify, [])
    client_id = Keyword.get(config, :client_id) || ""
    client_secret = Keyword.get(config, :client_secret) || ""

    [
      {~c"SPOTIPY_CLIENT_ID", String.to_charlist(client_id)},
      {~c"SPOTIPY_CLIENT_SECRET", String.to_charlist(client_secret)}
    ]
  end

  defp python_cmd do
    Application.get_env(:sound_forge, :python_cmd, "python3")
  end

  defp helper_script_path do
    Application.get_env(
      :sound_forge,
      :spotify_dl_script,
      Path.join(:code.priv_dir(:sound_forge), "python/spotify_dl.py")
    )
  end

  defp default_downloads_dir do
    Application.get_env(:sound_forge, :downloads_dir, "priv/uploads/downloads")
  end
end
