defmodule SoundForge.Audio.LalalAI do
  @moduledoc """
  HTTP client for the lalal.ai REST API (v1 + v1.1 endpoints).

  Handles audio file uploads, task status polling, stem file downloads,
  multistem/demuser/voice-clean splitting, voice changing, quota checks,
  and task lifecycle management for cloud-based stem separation.
  Uses the Req library for HTTP requests.

  ## API Key

  The API key is read from `Application.get_env(:sound_forge, :lalalai_api_key)`,
  which is populated from the `LALALAI_API_KEY` environment variable via
  `config/runtime.exs`. Authenticated via the `X-License-Key` header per
  the OpenAPI v1.1 spec.

  ## Idempotency Keys

  All split and voice change operations accept an optional `:idempotency_key`
  in their opts. When provided, the key is included in the API request body
  so that lalal.ai can de-duplicate identical requests. If the API responds
  with an `idempotency_key_used` error, `post_json/3` transparently recovers
  by returning `{:ok, body}` (which contains the existing task_id).

  Idempotency keys are generated automatically by `Music.create_processing_job/1`
  and stored in the ProcessingJob options map so that Oban retries reuse the
  same key rather than generating a new one per attempt.

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
      {:ok, result} = LalalAI.cancel_task(task_id)
      {:ok, minutes} = LalalAI.get_quota()

  """

  require Logger

  @base_url "https://www.lalal.ai/api"
  @default_timeout 30_000

  @type task_id :: String.t()
  @type source_id :: String.t()
  @type stem_filter :: String.t()
  @type status_response :: %{
          id: String.t(),
          status: String.t(),
          stem: map() | nil,
          back: map() | nil,
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

    case resolve_key() do
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
    case resolve_key() do
      nil ->
        {:error, :api_key_missing}

      key ->
        url = "#{@base_url}/check/"

        result =
          Req.get(url,
            headers: auth_headers(key),
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
  Returns the configured lalal.ai API key from LALALAI_API_KEY env var, or nil.
  """
  @spec api_key() :: String.t() | nil
  def api_key do
    Application.get_env(:sound_forge, :lalalai_api_key)
  end

  @doc """
  Returns the best available API key from any source:
  LALALAI_API_KEY env var, then SYSTEM_LALALAI_ACTIVATION_KEY.
  """
  @spec resolve_key() :: String.t() | nil
  def resolve_key do
    api_key() || system_key()
  end

  @doc """
  Returns true if lalal.ai is configured via any key source.
  """
  @spec configured?() :: boolean()
  def configured? do
    not is_nil(resolve_key())
  end

  @doc """
  Returns true if lalal.ai is configured for the given user.
  Checks user-level API key first, then falls back to Application env.
  """
  @spec configured_for_user?(integer() | nil) :: boolean()
  def configured_for_user?(user_id) do
    not is_nil(api_key_for_user(user_id))
  end

  @doc """
  Returns the system activation key configured for demo/pro-tier accounts.
  Sourced from the SYSTEM_LALALAI_ACTIVATION_KEY environment variable.
  """
  @spec system_key() :: String.t() | nil
  def system_key do
    Application.get_env(:sound_forge, :system_lalalai_key)
  end

  @doc """
  Resolves the API key for a given user.
  Priority:
  1. User's personal stored key (from user_settings)
  2. System activation key (SYSTEM_LALALAI_ACTIVATION_KEY, for demo/pro accounts)
  3. Global LALALAI_API_KEY (Application env fallback)
  """
  @spec api_key_for_user(integer() | nil) :: String.t() | nil
  def api_key_for_user(nil) do
    system_key() || api_key()
  end

  def api_key_for_user(user_id) when is_integer(user_id) do
    case SoundForge.Settings.get_user_settings(user_id) do
      %{lalalai_api_key: key} when is_binary(key) and byte_size(key) > 0 -> key
      _ -> system_key() || api_key()
    end
  end

  @doc """
  Tests whether a lalal.ai API key is valid by making a lightweight
  API call (a check request with a dummy task ID). Returns {:ok, :valid}
  if the key authenticates successfully, or {:error, reason} otherwise.

  A 200 response with an error about an unknown task ID means the key
  itself is valid. A 401/403 or auth-related error means invalid.
  """
  @spec test_api_key(String.t()) :: {:ok, :valid} | {:error, term()}
  def test_api_key(key) when is_binary(key) and byte_size(key) > 0 do
    url = "#{@base_url}/check/"

    result =
      Req.get(url,
        headers: [{"x-license-key", key}],
        params: [id: "test-key-validation"],
        receive_timeout: @default_timeout
      )

    case result do
      {:ok, %{status: 200, body: body}} ->
        case body do
          %{"status" => "error", "error" => msg} ->
            if String.contains?(String.downcase(to_string(msg)), "auth") do
              {:error, :invalid_api_key}
            else
              {:ok, :valid}
            end

          _ ->
            {:ok, :valid}
        end

      {:ok, %{status: 401}} ->
        {:error, :invalid_api_key}

      {:ok, %{status: 403}} ->
        {:error, :invalid_api_key}

      {:ok, %{status: status_code}} ->
        Logger.warning("lalal.ai key test returned HTTP #{status_code}")
        {:error, {:http_error, status_code}}

      {:error, reason} ->
        Logger.error("lalal.ai key test failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def test_api_key(_), do: {:error, :empty_api_key}

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

  # ---------------------------------------------------------------------------
  # v1.1 API endpoints
  # ---------------------------------------------------------------------------

  @doc """
  Uploads an audio file to lalal.ai using the v1.1 upload endpoint.

  Returns `{:ok, source_id}` on success. The `source_id` can then be
  passed to `split_demuser/2`, `split_multistem/3`, `split_voice_clean/3`,
  or `change_voice/2` to initiate processing.

  Unlike `upload_track/2`, this endpoint only uploads the file without
  starting any separation task. Processing must be initiated separately
  via one of the split endpoints.

  ## Parameters

    - `file_path` - Absolute path to the audio file to upload

  ## Examples

      {:ok, source_id} = LalalAI.upload_source("/path/to/audio.mp3")
      {:ok, result} = LalalAI.split_demuser(source_id, stem: "music")
  """
  @spec upload_source(String.t()) :: {:ok, source_id()} | {:error, term()}
  def upload_source(file_path) do
    with_api_key(fn key ->
      do_upload_source(file_path, key)
    end)
  end

  @doc """
  Cancels one or more running separation tasks.

  ## Parameters

    - `task_ids` - A single task ID string or list of task ID strings
    - `opts` - Keyword options (reserved for future use)

  ## Examples

      {:ok, result} = LalalAI.cancel_task("uuid-1234")
      {:ok, result} = LalalAI.cancel_task(["uuid-1234", "uuid-5678"])
  """
  @spec cancel_task(task_id() | [task_id()], keyword()) :: {:ok, map()} | {:error, term()}
  def cancel_task(task_ids, opts \\ [])

  def cancel_task(task_id, opts) when is_binary(task_id), do: cancel_task([task_id], opts)

  def cancel_task(task_ids, _opts) when is_list(task_ids) do
    with_api_key(fn key ->
      post_json("/v1/cancel/", %{"task_ids" => task_ids}, key)
    end)
  end

  @doc """
  Cancels all running separation tasks for the current account.

  ## Examples

      {:ok, result} = LalalAI.cancel_all_tasks()
  """
  @spec cancel_all_tasks() :: {:ok, map()} | {:error, term()}
  def cancel_all_tasks do
    with_api_key(fn key ->
      post_json("/v1/cancel/all/", %{}, key)
    end)
  end

  @doc """
  Deletes a previously uploaded source file from lalal.ai.

  ## Parameters

    - `source_id` - The source ID to delete
    - `opts` - Keyword options (reserved for future use)

  ## Examples

      {:ok, result} = LalalAI.delete_source("uuid-1234")
  """
  @spec delete_source(source_id(), keyword()) :: {:ok, map()} | {:error, term()}
  def delete_source(source_id, _opts \\ []) do
    with_api_key(fn key ->
      post_json("/v1/delete/", %{"source_id" => source_id}, key)
    end)
  end

  @doc """
  Returns the remaining quota in minutes for the current API key.

  ## Examples

      {:ok, 42.5} = LalalAI.get_quota()
  """
  @spec get_quota() :: {:ok, float()} | {:error, term()}
  def get_quota do
    with_api_key(fn key ->
      case post_json("/v1/limits/minutes_left/", %{}, key) do
        {:ok, %{"minutes_left" => minutes}} when is_number(minutes) ->
          {:ok, minutes / 1.0}

        {:ok, body} ->
          {:error, {:unexpected_response, body}}

        error ->
          error
      end
    end)
  end

  @doc """
  Initiates a multistem split, separating multiple stems from a source file
  in a single request.

  ## Parameters

    - `source_id` - The source file ID (from a prior upload)
    - `stem_list` - List of stem filter strings (e.g. `["vocals", "drum", "bass"]`)
    - `opts` - Keyword options:
      - `:splitter` - Splitting model (default: "phoenix")
      - `:dereverb` - Enable de-reverb (default: false)
      - `:encoder_format` - Output format, e.g. "wav", "mp3" (default: "wav")
      - `:extraction_level` - Extraction level (default: "normal")
      - `:idempotency_key` - UUID4 string for request deduplication (optional)

  ## Examples

      {:ok, result} = LalalAI.split_multistem("uuid-1234", ["vocals", "drum", "bass"])
  """
  @spec split_multistem(source_id(), [stem_filter()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def split_multistem(source_id, stem_list, opts \\ []) do
    with_api_key(fn key ->
      params = build_split_params(opts, %{"stem_list" => stem_list})

      body =
        %{"source_id" => source_id, "params" => params}
        |> maybe_put_idempotency_key(opts)

      post_json("/v1/split/multistem/", body, key)
    end)
  end

  @doc """
  Initiates a demuser split (music/vocal separation with the demuser engine).

  ## Parameters

    - `source_id` - The source file ID (from a prior upload)
    - `opts` - Keyword options:
      - `:stem` - Stem type (default: "music")
      - `:splitter` - Splitting model (default: "phoenix")
      - `:dereverb` - Enable de-reverb (default: false)
      - `:encoder_format` - Output format (default: "wav")
      - `:extraction_level` - Extraction level (default: "normal")
      - `:idempotency_key` - UUID4 string for request deduplication (optional)

  ## Examples

      {:ok, result} = LalalAI.split_demuser("uuid-1234", stem: "music", splitter: "orion")
  """
  @spec split_demuser(source_id(), keyword()) :: {:ok, map()} | {:error, term()}
  def split_demuser(source_id, opts \\ []) do
    with_api_key(fn key ->
      stem = Keyword.get(opts, :stem, "music")
      params = build_split_params(opts, %{"stem" => stem})

      body =
        %{"source_id" => source_id, "params" => params}
        |> maybe_put_idempotency_key(opts)

      post_json("/v1/split/demuser/", body, key)
    end)
  end

  @doc """
  Initiates a voice-clean split (vocal isolation with noise cancelling).

  ## Parameters

    - `source_id` - The source file ID (from a prior upload)
    - `noise_cancelling_level` - Noise cancelling intensity: 0, 1, or 2
    - `opts` - Keyword options:
      - `:splitter` - Splitting model (default: "phoenix")
      - `:dereverb` - Enable de-reverb (default: false)
      - `:encoder_format` - Output format (default: "wav")
      - `:extraction_level` - Extraction level (default: "normal")
      - `:idempotency_key` - UUID4 string for request deduplication (optional)

  ## Examples

      {:ok, result} = LalalAI.split_voice_clean("uuid-1234", 2)
  """
  @spec split_voice_clean(source_id(), 0 | 1 | 2, keyword()) ::
          {:ok, map()} | {:error, term()}
  def split_voice_clean(source_id, noise_cancelling_level, opts \\ [])
      when noise_cancelling_level in [0, 1, 2] do
    with_api_key(fn key ->
      params =
        build_split_params(opts, %{
          "stem" => "voice",
          "noise_cancelling_level" => noise_cancelling_level
        })

      body =
        %{"source_id" => source_id, "params" => params}
        |> maybe_put_idempotency_key(opts)

      post_json("/v1/split/voice_clean/", body, key)
    end)
  end

  @doc """
  Applies a voice pack transformation to a source file, changing the voice
  characteristics.

  ## Parameters

    - `source_id` - The source file ID (from a prior upload)
    - `opts` - Keyword options:
      - `:voice_pack_id` - ID of the voice pack to apply (required)
      - `:accent` - Accent intensity from 0.0 to 1.0 (default: 0.5)
      - `:tonality_reference` - `"source_file"` or `"voice_pack"` (default: "source_file")
      - `:dereverb` - Enable de-reverb (default: false)
      - `:encoder_format` - Output format (default: "wav")
      - `:idempotency_key` - UUID4 string for request deduplication (optional)

  ## Examples

      {:ok, result} = LalalAI.change_voice("uuid-1234", voice_pack_id: "pack-abc", accent: 0.7)
  """
  @spec change_voice(source_id(), keyword()) :: {:ok, map()} | {:error, term()}
  def change_voice(source_id, opts \\ []) do
    voice_pack_id = Keyword.get(opts, :voice_pack_id)
    accent = Keyword.get(opts, :accent, 0.5)
    tonality_reference = Keyword.get(opts, :tonality_reference, "source_file")
    dereverb = Keyword.get(opts, :dereverb, false)
    encoder_format = Keyword.get(opts, :encoder_format, "wav")

    unless voice_pack_id do
      raise ArgumentError, "change_voice/2 requires :voice_pack_id option"
    end

    with_api_key(fn key ->
      body =
        %{
          "source_id" => source_id,
          "params" => %{
            "voice_pack_id" => voice_pack_id,
            "accent" => accent,
            "tonality_reference" => tonality_reference,
            "dereverb_enabled" => dereverb,
            "encoder_format" => encoder_format
          }
        }
        |> maybe_put_idempotency_key(opts)

      post_json("/v1/change_voice/", body, key)
    end)
  end

  @doc """
  Lists available voice packs for voice changing.

  ## Examples

      {:ok, packs} = LalalAI.list_voice_packs()
  """
  @spec list_voice_packs() :: {:ok, list(map())} | {:error, term()}
  def list_voice_packs do
    with_api_key(fn key ->
      case post_json("/v1/voice_packs/list/", %{}, key) do
        {:ok, %{"packs" => packs}} when is_list(packs) ->
          {:ok, packs}

        {:ok, body} ->
          {:error, {:unexpected_response, body}}

        error ->
          error
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp auth_headers(key), do: [{"x-license-key", key}]

  # Conditionally adds an idempotency key to the request body map if
  # provided in opts. The lalal.ai API accepts an optional idempotency_key
  # field to prevent duplicate processing of the same request.
  defp maybe_put_idempotency_key(body, opts) do
    case Keyword.get(opts, :idempotency_key) do
      nil -> body
      key when is_binary(key) -> Map.put(body, "idempotency_key", key)
    end
  end

  # Wraps an API call that requires an API key, returning {:error, :api_key_missing}
  # if no key is configured via any source (env, system, or user).
  defp with_api_key(fun) do
    case resolve_key() do
      nil -> {:error, :api_key_missing}
      key -> fun.(key)
    end
  end

  # Generic POST helper for JSON-body v1.1 endpoints.
  # Returns {:ok, body} on 200 or {:error, reason} otherwise.
  # Handles idempotency_key_used responses by extracting the existing task_id
  # and returning {:ok, body} so callers can proceed with the existing task.
  defp post_json(path, body, key) do
    url = "#{@base_url}#{path}"

    result =
      Req.post(url,
        headers: auth_headers(key),
        json: body,
        receive_timeout: @default_timeout
      )

    case result do
      {:ok, %{status: 200, body: resp_body}} ->
        {:ok, resp_body}

      {:ok, %{status: status_code, body: resp_body}} ->
        case detect_idempotency_reuse(resp_body) do
          {:reused, task_id} ->
            Logger.info(
              "lalal.ai idempotency_key_used on POST #{path} " <>
                "(HTTP #{status_code}), existing task_id=#{task_id}"
            )

            {:ok, resp_body}

          :not_reused ->
            Logger.warning(
              "lalal.ai POST #{path} returned #{status_code}: #{inspect(resp_body)}"
            )

            {:error, {:http_error, status_code, resp_body}}
        end

      {:error, reason} ->
        Logger.error("lalal.ai POST #{path} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Detects whether a lalal.ai response indicates an idempotency key was
  # already used. The API may return the existing task_id in the response body.
  # Returns {:reused, task_id} if the key was reused, :not_reused otherwise.
  @spec detect_idempotency_reuse(map() | term()) :: {:reused, String.t()} | :not_reused
  defp detect_idempotency_reuse(%{"error" => error} = body) when is_binary(error) do
    if String.contains?(String.downcase(error), "idempotency_key_used") do
      task_id = Map.get(body, "task_id") || Map.get(body, "id")
      {:reused, task_id || "unknown"}
    else
      :not_reused
    end
  end

  defp detect_idempotency_reuse(%{"status" => "error", "error" => %{"code" => code}} = body)
       when is_binary(code) do
    if String.contains?(String.downcase(code), "idempotency_key_used") do
      task_id =
        get_in(body, ["error", "task_id"]) ||
          Map.get(body, "task_id") ||
          Map.get(body, "id")

      {:reused, task_id || "unknown"}
    else
      :not_reused
    end
  end

  defp detect_idempotency_reuse(_), do: :not_reused

  # Builds the common params map for split endpoints from opts keyword list.
  # Merges any `extras` map entries on top of the common fields.
  defp build_split_params(opts, extras) do
    splitter = Keyword.get(opts, :splitter, "phoenix")
    dereverb = Keyword.get(opts, :dereverb, false)
    encoder_format = Keyword.get(opts, :encoder_format, "wav")
    extraction_level = Keyword.get(opts, :extraction_level, "normal")

    %{
      "splitter" => splitter,
      "dereverb_enabled" => dereverb,
      "encoder_format" => encoder_format,
      "extraction_level" => extraction_level
    }
    |> Map.merge(extras)
  end

  defp do_upload(file_path, stem_filter, enhanced, splitter, api_key) do
    Logger.info(
      "Uploading track to lalal.ai: #{Path.basename(file_path)}, filter=#{stem_filter}"
    )

    url = "#{@base_url}/upload/"

    multipart =
      Req.new()
      |> Req.merge(
        headers: auth_headers(api_key),
        receive_timeout: 120_000
      )

    result =
      Req.post(multipart,
        url: url,
        form_multipart: [
          {"stem_filter", stem_filter},
          {"enhanced_processing", if(enhanced, do: "1", else: "0")},
          {"splitter", splitter},
          {"file",
           {File.stream!(file_path),
            filename: Path.basename(file_path),
            content_type: detect_content_type(file_path)}}
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

  defp do_upload_source(file_path, api_key) do
    Logger.info("Uploading source to lalal.ai (v1.1): #{Path.basename(file_path)}")

    url = "#{@base_url}/v1/upload/"
    content_type = detect_content_type(file_path)
    filename = Path.basename(file_path)

    result =
      Req.post(url,
        headers:
          auth_headers(api_key) ++
            [
              {"content-type", content_type},
              {"content-disposition", "attachment; filename=#{filename}"}
            ],
        body: File.read!(file_path),
        receive_timeout: 120_000
      )

    case result do
      {:ok, %{status: 200, body: %{"id" => source_id}}} ->
        Logger.info("lalal.ai v1.1 upload complete, source_id=#{source_id}")
        {:ok, source_id}

      {:ok, %{status: status_code, body: body}} ->
        Logger.error("lalal.ai v1.1 upload returned #{status_code}: #{inspect(body)}")
        {:error, {:http_error, status_code, body}}

      {:error, reason} ->
        Logger.error("lalal.ai v1.1 upload failed: #{inspect(reason)}")
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
          back: Map.get(task_data, "back"),
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
          back: Map.get(task_data, "back"),
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
