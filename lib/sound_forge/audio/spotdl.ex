defmodule SoundForge.Audio.SpotDL do
  @moduledoc """
  Wrapper around the spotdl CLI for Spotify metadata extraction and audio downloading.

  spotdl handles URL parsing, metadata fetching, and downloading for tracks,
  albums, and playlists from Spotify URLs. This replaces the Spotify Web API
  for the main pipeline flow.
  """

  require Logger

  @spotdl_cmd "spotdl"

  @doc """
  Fetches metadata for a Spotify URL using `spotdl save`.

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
    args = ["save", url, "--save-file", "-", "--log-level", "ERROR"]
    args = args ++ spotify_auth_args()

    Logger.info("Fetching metadata via spotdl for #{url}")

    case System.cmd(spotdl_cmd(), args, stderr_to_stdout: true) do
      {output, 0} ->
        parse_save_output(output)

      {error_output, code} ->
        Logger.error("spotdl save failed (exit #{code}): #{String.slice(error_output, 0, 500)}")
        {:error, "Failed to fetch metadata: #{String.slice(error_output, 0, 200)}"}
    end
  rescue
    e in ErlangError ->
      {:error, "spotdl not available: #{inspect(e)}"}
  end

  @doc """
  Downloads a track from a Spotify URL using `spotdl download`.

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
    output_dir = Keyword.get(opts, :output_dir, default_downloads_dir())
    format = Keyword.get(opts, :format, "mp3")
    bitrate = Keyword.get(opts, :bitrate, "320k")
    output_template = Keyword.get(opts, :output_template, "{track-id}")

    File.mkdir_p!(output_dir)

    output_path = Path.join(output_dir, "#{output_template}.#{format}")

    args =
      [
        "download",
        url,
        "--output",
        output_path,
        "--format",
        format,
        "--bitrate",
        bitrate,
        "--log-level",
        "ERROR"
      ] ++ spotify_auth_args()

    Logger.info("Starting spotdl download for #{url}")

    case System.cmd(spotdl_cmd(), args,
           stderr_to_stdout: true,
           cd: output_dir
         ) do
      {_output, 0} ->
        find_downloaded_file(output_dir, output_template, format)

      {error_output, code} ->
        Logger.error(
          "spotdl download failed (exit #{code}): #{String.slice(error_output, 0, 500)}"
        )

        {:error, "Download failed: #{String.slice(error_output, 0, 200)}"}
    end
  rescue
    e in ErlangError ->
      {:error, "spotdl not available: #{inspect(e)}"}
  end

  @doc """
  Checks if spotdl is available on the system.
  """
  @spec available?() :: boolean()
  def available? do
    case System.cmd(spotdl_cmd(), ["--version"], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  # -- Private --

  defp parse_save_output(output) do
    # spotdl save --save-file - outputs JSON array of track objects to stdout
    # But it may also print log lines before the JSON, so we need to find the JSON
    output = String.trim(output)

    json_str = extract_json_array(output)

    case Jason.decode(json_str) do
      {:ok, tracks} when is_list(tracks) and length(tracks) > 0 ->
        {:ok, tracks}

      {:ok, []} ->
        {:error, "No tracks found for this URL"}

      {:ok, _} ->
        {:error, "Unexpected response format from spotdl"}

      {:error, _} ->
        {:error, "Failed to parse spotdl output"}
    end
  end

  defp extract_json_array(output) do
    # Find the JSON array in the output (starts with [ and ends with ])
    case Regex.run(~r/\[[\s\S]*\]\s*$/m, output) do
      [json] -> json
      _ -> output
    end
  end

  defp find_downloaded_file(output_dir, template, format) do
    # Look for the file that was downloaded
    expected = Path.join(output_dir, "#{template}.#{format}")

    if File.exists?(expected) do
      {:ok, %{size: size}} = File.stat(expected)
      {:ok, %{path: expected, size: size}}
    else
      # spotdl may have used a sanitized filename; find recently created files
      case Path.wildcard(Path.join(output_dir, "*.#{format}"))
           |> Enum.filter(fn f ->
             case File.stat(f) do
               {:ok, %{mtime: mtime}} ->
                 # File created in the last 60 seconds
                 case NaiveDateTime.from_erl(mtime) do
                   {:ok, ndt} -> NaiveDateTime.diff(NaiveDateTime.utc_now(), ndt) < 60
                   _ -> false
                 end

               _ ->
                 false
             end
           end)
           |> Enum.sort_by(fn f -> File.stat!(f).mtime end, :desc) do
        [newest | _] ->
          {:ok, %{size: size}} = File.stat(newest)
          {:ok, %{path: newest, size: size}}

        [] ->
          {:error, "Downloaded file not found in #{output_dir}"}
      end
    end
  end

  defp spotify_auth_args do
    config = Application.get_env(:sound_forge, :spotify, [])
    client_id = Keyword.get(config, :client_id)
    client_secret = Keyword.get(config, :client_secret)

    cond do
      is_binary(client_id) and client_id != "" and
        is_binary(client_secret) and client_secret != "" ->
        ["--client-id", client_id, "--client-secret", client_secret]

      true ->
        []
    end
  end

  defp spotdl_cmd do
    Application.get_env(:sound_forge, :spotdl_cmd, @spotdl_cmd)
  end

  defp default_downloads_dir do
    Application.get_env(:sound_forge, :downloads_dir, "priv/uploads/downloads")
  end
end
