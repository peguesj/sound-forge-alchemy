defmodule SoundForge.Audio.LalalAI do
  @moduledoc """
  HTTP client for the lalal.ai REST API.

  Handles audio file uploads, task status polling, and stem file downloads
  for cloud-based stem separation. Uses the Req library for HTTP requests.

  ## API Key

  The API key is read from `Application.get_env(:sound_forge, :lalalai_api_key)`,
  which is populated from the `LALALAI_API_KEY` environment variable via
  `config/runtime.exs`.

  ## Stem Filters

  lalal.ai supports the following stem filters:
  - `"vocals"` - Vocal track
  - `"drum"` - Drum track
  - `"bass"` - Bass track
  - `"piano"` - Piano track
  - `"electricguitar"` - Electric guitar track
  - `"acousticguitar"` - Acoustic guitar track
  - `"synthesizer"` - Synthesizer/synth track
  - `"strings"` - String instruments
  - `"winds"` - Wind instruments
  - `"noise"` - Background noise
  - `"midside"` - Mid/Side separation

  ## Usage

      {:ok, task_id} = LalalAI.upload_track("/path/to/audio.mp3")
      {:ok, status} = LalalAI.get_status(task_id)
      {:ok, file_path} = LalalAI.download_stem(url, "/path/to/output.wav")

  """

  require Logger

  @base_url "https://www.lalal.ai/api"
  @default_timeout 30_000

  @type task_id :: String.t()
  @type stem_filter :: String.t()
  @type status_response :: %{
          id: String.t(),
          status: String.t(),
          stem: map() | nil,
          accompaniment: map() | nil,
          error: String.t() | nil,
          queue_progress: integer() | nil
        }

  @doc """
  Uploads an audio file to lalal.ai for stem separation.

  Returns `{:ok, task_id}` on success, where `task_id` can be used to poll
  for status and download results.

  ## Parameters

    - `file_path` - Absolute path to the audio file to upload
    - `opts` - Keyword options:
      - `:stem_filter` - The stem type to separate (default: "vocals"). See module docs for valid values.
      - `:enhanced_processing` - Boolean, enables enhanced quality mode (default: false)
      - `:splitter` - The splitting model to use (default: "phoenix"). Options: "phoenix", "orion", "cassiopeia"
  """
  @spec upload_track(String.t(), keyword()) :: {:ok, task_id()} | {:error, term()}
  def upload_track(file_path, opts \\ []) do
    stem_filter = Keyword.get(opts, :stem_filter, "vocals")
    enhanced = Keyword.get(opts, :enhanced_processing, false)
    splitter = Keyword.get(opts, :splitter, "phoenix")

    case api_key() do
      nil ->
        {:error, :api_key_missing}

      key ->
        do_upload(file_path, stem_filter, enhanced, splitter, key)
    end
  end

  @doc """
  Polls lalal.ai for the status of a separation task.

  Returns `{:ok, status_response}` where status is one of:
  - `"queued"` - Task is in queue
  - `"progress"` - Task is being processed
  - `"success"` - Task completed successfully
  - `"error"` - Task failed

  ## Parameters

    - `task_id` - The task ID returned by `upload_track/2`
  """
  @spec get_status(task_id()) :: {:ok, status_response()} | {:error, term()}
  def get_status(task_id) do
    case api_key() do
      nil ->
        {:error, :api_key_missing}

      key ->
        url = "#{@base_url}/check/"

        result =
          Req.get(url,
            headers: [{"authorization", "license #{key}"}],
            params: [id: task_id],
            receive_timeout: @default_timeout
          )

        case result do
          {:ok, %{status: 200, body: body}} ->
            parse_status_response(body)

          {:ok, %{status: status_code, body: body}} ->
            Logger.warning("lalal.ai status check returned #{status_code}: #{inspect(body)}")
            {:error, {:http_error, status_code}}

          {:error, reason} ->
            Logger.error("lalal.ai status check failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Downloads a stem file from the given URL and saves it to `output_path`.

  Returns `{:ok, output_path}` on success.

  ## Parameters

    - `url` - The download URL from the lalal.ai status response
    - `output_path` - Absolute path where the file should be saved
  """
  @spec download_stem(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def download_stem(url, output_path) do
    Logger.info("Downloading stem from lalal.ai to #{output_path}")

    result =
      Req.get(url,
        receive_timeout: 120_000,
        into: File.stream!(output_path, [:write, :binary])
      )

    case result do
      {:ok, %{status: 200}} ->
        {:ok, output_path}

      {:ok, %{status: status_code}} ->
        File.rm(output_path)
        Logger.error("lalal.ai download returned HTTP #{status_code}")
        {:error, {:http_error, status_code}}

      {:error, reason} ->
        File.rm(output_path)
        Logger.error("lalal.ai download failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Returns the configured lalal.ai API key, or nil if not configured.
  """
  @spec api_key() :: String.t() | nil
  def api_key do
    Application.get_env(:sound_forge, :lalalai_api_key)
  end

  @doc """
  Returns true if lalal.ai is configured (API key is present).
  """
  @spec configured?() :: boolean()
  def configured? do
    not is_nil(api_key())
  end

  @doc """
  Returns the list of supported stem filter names for lalal.ai.
  """
  @spec stem_filters() :: [String.t()]
  def stem_filters do
    ~w(vocals drum bass piano electricguitar acousticguitar synthesizer strings winds noise midside)
  end

  @doc """
  Maps a lalal.ai stem filter name to the internal SFA stem type atom.

  ## Examples

      iex> LalalAI.filter_to_stem_type("electricguitar")
      :electric_guitar

      iex> LalalAI.filter_to_stem_type("vocals")
      :vocals

      iex> LalalAI.filter_to_stem_type("unknown")
      nil
  """
  @spec filter_to_stem_type(String.t()) :: atom() | nil
  def filter_to_stem_type(filter) do
    Map.get(filter_stem_map(), filter)
  end

  # Private helpers

  defp do_upload(file_path, stem_filter, enhanced, splitter, api_key) do
    Logger.info("Uploading track to lalal.ai: #{Path.basename(file_path)}, filter=#{stem_filter}")

    url = "#{@base_url}/upload/"

    multipart =
      Req.new()
      |> Req.merge(
        headers: [{"authorization", "license #{api_key}"}],
        receive_timeout: 120_000
      )

    result =
      Req.post(multipart,
        url: url,
        form_multipart: [
          {"stem_filter", stem_filter},
          {"enhanced_processing", if(enhanced, do: "1", else: "0")},
          {"splitter", splitter},
          {:file, file_path, content_type: detect_content_type(file_path)}
        ]
      )

    case result do
      {:ok, %{status: 200, body: body}} ->
        parse_upload_response(body)

      {:ok, %{status: status_code, body: body}} ->
        Logger.error("lalal.ai upload returned #{status_code}: #{inspect(body)}")
        {:error, {:http_error, status_code, body}}

      {:error, reason} ->
        Logger.error("lalal.ai upload failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_upload_response(%{"status" => "success", "id" => task_id}) do
    {:ok, task_id}
  end

  defp parse_upload_response(%{"status" => "error", "error" => message}) do
    {:error, {:api_error, message}}
  end

  defp parse_upload_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parse_upload_response(parsed)
      {:error, _} -> {:error, {:parse_error, body}}
    end
  end

  defp parse_upload_response(body) do
    {:error, {:unexpected_response, body}}
  end

  defp parse_status_response(%{"status" => "success", "result" => result}) do
    task =
      result
      |> Map.get("result", %{})
      |> Enum.reduce(%{}, fn {task_id, task_data}, acc ->
        Map.put(acc, task_id, task_data)
      end)

    # Extract the single task from the result map
    case Map.to_list(task) do
      [{task_id, task_data}] ->
        status = %{
          id: task_id,
          status: Map.get(task_data, "status", "unknown"),
          stem: Map.get(task_data, "stem"),
          accompaniment: Map.get(task_data, "accompaniment"),
          error: Map.get(task_data, "error"),
          queue_progress: Map.get(task_data, "queue_progress")
        }

        {:ok, status}

      [] ->
        {:error, :empty_result}

      multiple ->
        # Return first task if multiple (shouldn't happen for single upload)
        {task_id, task_data} = hd(multiple)

        status = %{
          id: task_id,
          status: Map.get(task_data, "status", "unknown"),
          stem: Map.get(task_data, "stem"),
          accompaniment: Map.get(task_data, "accompaniment"),
          error: Map.get(task_data, "error"),
          queue_progress: Map.get(task_data, "queue_progress")
        }

        {:ok, status}
    end
  end

  defp parse_status_response(%{"status" => "error", "error" => message}) do
    {:error, {:api_error, message}}
  end

  defp parse_status_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parse_status_response(parsed)
      {:error, _} -> {:error, {:parse_error, body}}
    end
  end

  defp parse_status_response(body) do
    {:error, {:unexpected_response, body}}
  end

  defp detect_content_type(file_path) do
    case Path.extname(file_path) |> String.downcase() do
      ".mp3" -> "audio/mpeg"
      ".wav" -> "audio/wav"
      ".flac" -> "audio/flac"
      ".ogg" -> "audio/ogg"
      ".m4a" -> "audio/mp4"
      ".aac" -> "audio/aac"
      _ -> "application/octet-stream"
    end
  end

  defp filter_stem_map do
    %{
      "vocals" => :vocals,
      "drum" => :drums,
      "bass" => :bass,
      "piano" => :piano,
      "electricguitar" => :electric_guitar,
      "acousticguitar" => :acoustic_guitar,
      "synthesizer" => :synth,
      "strings" => :strings,
      "winds" => :wind,
      "noise" => :other,
      "midside" => :other
    }
  end
end
