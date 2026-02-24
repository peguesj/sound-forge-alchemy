defmodule SoundForge.Audio.AnalyzerPort do
  @moduledoc """
  Erlang Port wrapper for librosa-based audio analysis.

  Provides supervised Port communication with the Python analyzer script
  for extracting audio features (tempo, key, energy, spectral, mfcc, chroma,
  structure, loop_points, arrangement, energy_curve).

  ## Usage

      {:ok, pid} = AnalyzerPort.start_link()
      {:ok, results} = AnalyzerPort.analyze("/path/to/audio.mp3", ["tempo", "key", "energy"])

  ## Features

  - tempo: BPM and beat tracking
  - key: Musical key detection (major/minor)
  - energy: RMS energy and zero-crossing rate
  - spectral: Spectral centroid, rolloff, bandwidth, contrast
  - mfcc: Mel-frequency cepstral coefficients
  - chroma: Chromagram features
  - structure: Song section segmentation (intro, verse, chorus, bridge, outro)
  - loop_points: Detected loop regions with start/end timestamps and confidence
  - arrangement: High-level arrangement map combining structure and energy flow
  - energy_curve: Per-beat energy envelope for waveform visualization
  - all: Extract all available features

  ## Port Protocol

  The Python script communicates via JSON over stdin/stdout:
  - Input: Command-line arguments
  - Output: Single JSON object on stdout
  - Errors: JSON error object on stderr, non-zero exit code
  """

  use GenServer
  require Logger

  @default_timeout 120_000
  @valid_features ~w(tempo key energy spectral mfcc chroma structure loop_points arrangement energy_curve all)

  # Client API

  @doc """
  Starts the analyzer port GenServer.
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
  Analyzes an audio file and extracts requested features.

  ## Parameters

    - audio_path: Path to the audio file
    - features: List of features to extract (default: ["tempo", "key", "energy"])

  ## Returns

    - `{:ok, results}` - Analysis results as a map
    - `{:error, reason}` - Error reason

  ## Examples

      {:ok, results} = AnalyzerPort.analyze("/path/to/song.mp3")
      {:ok, results} = AnalyzerPort.analyze("/path/to/song.mp3", ["tempo", "key"])
      {:ok, results} = AnalyzerPort.analyze("/path/to/song.mp3", ["all"])
  """
  def analyze(audio_path, features \\ ["tempo", "key", "energy"], opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)

    case validate_features(features) do
      :ok ->
        GenServer.call(server, {:analyze, audio_path, features}, analyzer_timeout())

      {:error, invalid} ->
        {:error, {:invalid_features, invalid}}
    end
  end

  @doc """
  Validates that all requested features are supported.
  """
  def validate_features(features) do
    invalid = Enum.reject(features, &(&1 in @valid_features))

    if Enum.empty?(invalid) do
      :ok
    else
      {:error, invalid}
    end
  end

  @doc """
  Returns the list of valid features.
  """
  def valid_features, do: @valid_features

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{port: nil, caller: nil, buffer: ""}}
  end

  @impl true
  def handle_call({:analyze, audio_path, features}, from, state) do
    case find_python() do
      {:ok, python} ->
        case find_analyzer_script() do
          {:ok, script} ->
            port = open_port(python, script, audio_path, features)
            {:noreply, %{state | port: port, caller: from, buffer: ""}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port, buffer: buffer} = state) do
    # Accumulate data in buffer
    new_buffer = buffer <> data
    {:noreply, %{state | buffer: new_buffer}}
  end

  @impl true
  def handle_info(
        {port, {:exit_status, 0}},
        %{port: port, caller: caller, buffer: buffer} = state
      ) do
    # Success - parse JSON output
    result = parse_output(buffer)
    GenServer.reply(caller, result)
    {:noreply, reset_state(state)}
  end

  @impl true
  def handle_info(
        {port, {:exit_status, code}},
        %{port: port, caller: caller, buffer: buffer} = state
      ) do
    # Failure - try to parse error from buffer
    error = parse_error(buffer, code)
    GenServer.reply(caller, {:error, error})
    {:noreply, reset_state(state)}
  end

  # Private Helpers

  defp analyzer_timeout do
    Application.get_env(:sound_forge, :analyzer_timeout, @default_timeout)
  end

  defp find_python do
    case System.find_executable("python3") || System.find_executable("python") do
      nil -> {:error, :python_not_found}
      python -> {:ok, python}
    end
  end

  defp find_analyzer_script do
    script_path = Path.join(:code.priv_dir(:sound_forge), "python/analyzer.py")

    if File.exists?(script_path) do
      {:ok, script_path}
    else
      {:error, {:script_not_found, script_path}}
    end
  end

  defp open_port(python, script, audio_path, features) do
    features_arg = Enum.join(features, ",")

    args = [
      script,
      audio_path,
      "--features",
      features_arg,
      "--output",
      "json"
    ]

    Logger.debug("Opening analyzer port: #{python} #{Enum.join(args, " ")}")

    Port.open({:spawn_executable, python}, [
      :binary,
      :exit_status,
      args: args
    ])
  end

  defp parse_output(buffer) do
    trimmed = String.trim(buffer)

    case Jason.decode(trimmed) do
      {:ok, result} ->
        {:ok, result}

      {:error, _} ->
        {:error, {:parse_error, trimmed}}
    end
  end

  defp parse_error(buffer, exit_code) do
    trimmed = String.trim(buffer)

    case Jason.decode(trimmed) do
      {:ok, %{"error" => error_type, "message" => message}} ->
        {:error_from_script, error_type, message}

      {:ok, %{"error" => error}} ->
        {:error_from_script, error}

      _ ->
        {:exit_code, exit_code, trimmed}
    end
  end

  defp reset_state(state) do
    %{state | port: nil, caller: nil, buffer: ""}
  end
end
