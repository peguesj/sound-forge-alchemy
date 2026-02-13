defmodule SoundForge.Audio.DemucsPort do
  @moduledoc """
  Erlang Port wrapper for Demucs stem separation.

  Provides supervised Port communication with the Demucs Python wrapper
  for separating audio into stems (vocals, drums, bass, other).

  ## Usage

      {:ok, pid} = DemucsPort.start_link()
      {:ok, stems} = DemucsPort.separate("/path/to/audio.mp3")
      {:ok, stems} = DemucsPort.separate("/path/to/audio.mp3", model: "htdemucs_ft")

  ## Models

  - htdemucs (default): Hybrid Transformer Demucs
  - htdemucs_ft: Fine-tuned version
  - mdx_extra: Extra quality model (slower)

  ## Port Protocol

  The Python script communicates via JSON over stdout:
  - Progress updates: `{"type": "progress", "percent": 50, "message": "..."}`
  - Final result: `{"type": "result", "stems": {...}, "model": "...", "output_dir": "..."}`
  - Errors: `{"type": "error", "message": "..."}`
  """

  use GenServer
  require Logger

  @default_timeout 300_000
  @valid_models ~w(htdemucs htdemucs_ft htdemucs_6s mdx_extra)
  @default_model "htdemucs"

  # Client API

  @doc """
  Starts the Demucs port GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Separates an audio file into stems.

  ## Parameters

    - audio_path: Path to the audio file
    - opts: Keyword list of options
      - `:model` - Demucs model to use (default: "htdemucs")
      - `:output_dir` - Output directory (default: "/tmp/demucs")
      - `:progress_callback` - Function called with progress updates

  ## Returns

    - `{:ok, result}` - Result map with stem paths
    - `{:error, reason}` - Error reason

  ## Examples

      {:ok, result} = DemucsPort.separate("/path/to/song.mp3")
      {:ok, result} = DemucsPort.separate("/path/to/song.mp3", model: "htdemucs_ft")
      {:ok, result} = DemucsPort.separate("/path/to/song.mp3",
        model: "mdx_extra",
        output_dir: "/custom/output",
        progress_callback: fn pct, message -> Logger.info("\#{pct}%: \#{message}") end
      )
  """
  def separate(audio_path, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    output_dir = Keyword.get(opts, :output_dir, demucs_output_dir())
    progress_callback = Keyword.get(opts, :progress_callback)

    server = Keyword.get(opts, :server, __MODULE__)

    # Validate model
    case validate_model(model) do
      :ok ->
        GenServer.call(
          server,
          {:separate, audio_path, model, output_dir, progress_callback},
          demucs_timeout()
        )

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates that the model is supported.
  """
  def validate_model(model) when model in @valid_models, do: :ok
  def validate_model(model), do: {:error, {:invalid_model, model}}

  @doc """
  Returns the list of valid models.
  """
  def valid_models, do: @valid_models

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{port: nil, caller: nil, buffer: "", progress_callback: nil, parsed_result: nil}}
  end

  @impl true
  def handle_call({:separate, audio_path, model, output_dir, progress_callback}, from, state) do
    case find_python() do
      {:ok, python} ->
        case find_demucs_script() do
          {:ok, script} ->
            port = open_port(python, script, audio_path, model, output_dir)

            {:noreply,
             %{state | port: port, caller: from, buffer: "", progress_callback: progress_callback}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port, buffer: buffer} = state) do
    # Accumulate data and try to parse JSON lines
    new_buffer = buffer <> data
    {lines, remaining} = extract_lines(new_buffer)

    # Process each complete JSON line, capturing result/error if present
    state =
      Enum.reduce(lines, state, fn line, acc ->
        process_json_line(line, acc)
      end)

    {:noreply, %{state | buffer: remaining}}
  end

  @impl true
  def handle_info(
        {port, {:exit_status, 0}},
        %{port: port, caller: caller, parsed_result: parsed_result, buffer: buffer} = state
      ) do
    # Use pre-parsed result if available, otherwise try to parse from remaining buffer
    result =
      case parsed_result do
        {:ok, _} = ok -> ok
        _ -> parse_final_result(buffer)
      end

    GenServer.reply(caller, result)
    {:noreply, reset_state(state)}
  end

  @impl true
  def handle_info(
        {port, {:exit_status, code}},
        %{port: port, caller: caller, parsed_result: parsed_result, buffer: buffer} = state
      ) do
    # Use pre-parsed error if available, otherwise try to parse from remaining buffer
    error =
      case parsed_result do
        {:error, message} -> {:error_from_script, message}
        _ -> parse_error(buffer, code)
      end

    GenServer.reply(caller, {:error, error})
    {:noreply, reset_state(state)}
  end

  # Private Helpers

  defp demucs_timeout do
    Application.get_env(:sound_forge, :demucs_timeout, @default_timeout)
  end

  defp demucs_output_dir do
    Application.get_env(:sound_forge, :demucs_output_dir, "/tmp/demucs")
  end

  defp find_python do
    case System.find_executable("python3") || System.find_executable("python") do
      nil -> {:error, :python_not_found}
      python -> {:ok, python}
    end
  end

  defp find_demucs_script do
    script_path = Path.join(:code.priv_dir(:sound_forge), "python/demucs_runner.py")

    if File.exists?(script_path) do
      {:ok, script_path}
    else
      {:error, {:script_not_found, script_path}}
    end
  end

  defp open_port(python, script, audio_path, model, output_dir) do
    args = [
      "-u",
      script,
      audio_path,
      "--model",
      model,
      "--output",
      output_dir
    ]

    Logger.debug("Opening Demucs port: #{python} #{Enum.join(args, " ")}")

    Port.open({:spawn_executable, python}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      args: args
    ])
  end

  defp extract_lines(buffer) do
    lines = String.split(buffer, "\n")

    {incomplete, complete_lines} = List.pop_at(lines, -1)
    {complete_lines, incomplete || ""}
  end

  defp process_json_line(line, state) do
    trimmed = String.trim(line)

    if trimmed == "" do
      state
    else
      case Jason.decode(trimmed) do
        {:ok, %{"type" => "progress", "percent" => percent, "message" => message}} ->
          handle_progress(percent, message, state)
          state

        {:ok, %{"type" => "error", "message" => message}} ->
          %{state | parsed_result: {:error, message}}

        {:ok, %{"type" => "result", "stems" => stems, "model" => model, "output_dir" => dir}} ->
          %{state | parsed_result: {:ok, %{stems: stems, model: model, output_dir: dir}}}

        {:ok, %{"type" => "result"} = data} ->
          %{state | parsed_result: {:ok, data}}

        _ ->
          Logger.debug("Unrecognized output: #{trimmed}")
          state
      end
    end
  end

  defp handle_progress(percent, message, %{progress_callback: callback})
       when is_function(callback) do
    callback.(percent, message)
  end

  defp handle_progress(percent, message, _state) do
    Logger.info("Demucs progress: #{percent}% - #{message}")
  end

  defp parse_final_result(buffer) do
    # Try to find the last complete JSON object in buffer
    lines = buffer |> String.trim() |> String.split("\n")

    result =
      lines
      |> Enum.reverse()
      |> Enum.find_value(fn line ->
        case Jason.decode(String.trim(line)) do
          {:ok, %{"type" => "result"} = data} -> {:ok, data}
          _ -> nil
        end
      end)

    case result do
      {:ok, %{"stems" => stems, "model" => model, "output_dir" => output_dir}} ->
        {:ok, %{stems: stems, model: model, output_dir: output_dir}}

      _ ->
        {:error, {:parse_error, buffer}}
    end
  end

  defp parse_error(buffer, exit_code) do
    lines = buffer |> String.trim() |> String.split("\n")

    error =
      lines
      |> Enum.reverse()
      |> Enum.find_value(fn line ->
        case Jason.decode(String.trim(line)) do
          {:ok, %{"type" => "error", "message" => message}} -> {:error_from_script, message}
          _ -> nil
        end
      end)

    error || {:exit_code, exit_code, buffer}
  end

  defp reset_state(state) do
    %{state | port: nil, caller: nil, buffer: "", progress_callback: nil, parsed_result: nil}
  end
end
