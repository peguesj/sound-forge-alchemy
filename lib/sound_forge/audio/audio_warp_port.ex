defmodule SoundForge.Audio.AudioWarpPort do
  @moduledoc """
  Erlang Port wrapper for pyrubberband-based audio warping.

  Provides supervised Port communication with the Python audio_warp script
  for time-stretching and pitch-shifting audio files.

  ## Usage

      {:ok, pid} = AudioWarpPort.start_link()
      {:ok, result} = AudioWarpPort.warp("/path/to/input.wav", tempo_factor: 1.2, pitch_semitones: -2)
  """

  use GenServer
  require Logger

  @default_timeout 120_000

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Warps an audio file with time-stretch and/or pitch-shift.

  ## Options

    - `:tempo_factor` - Speed multiplier (default: 1.0)
    - `:pitch_semitones` - Pitch shift in semitones (default: 0)
    - `:output_path` - Output file path (default: auto-generated)

  Returns `{:ok, %{"output_path" => path, "duration" => float}}`.
  """
  def warp(input_path, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    tempo_factor = Keyword.get(opts, :tempo_factor, 1.0)
    pitch_semitones = Keyword.get(opts, :pitch_semitones, 0)
    output_path = Keyword.get(opts, :output_path, default_output_path(input_path))

    GenServer.call(
      server,
      {:warp, input_path, output_path, tempo_factor, pitch_semitones},
      @default_timeout
    )
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{port: nil, caller: nil, buffer: ""}}
  end

  @impl true
  def handle_call({:warp, input_path, output_path, tempo_factor, pitch_semitones}, from, state) do
    case find_python() do
      {:ok, python} ->
        case find_script() do
          {:ok, script} ->
            port = open_port(python, script, input_path, output_path, tempo_factor, pitch_semitones)
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
    {:noreply, %{state | buffer: buffer <> data}}
  end

  @impl true
  def handle_info(
        {port, {:exit_status, 0}},
        %{port: port, caller: caller, buffer: buffer} = state
      ) do
    result = parse_output(buffer)
    GenServer.reply(caller, result)
    {:noreply, reset_state(state)}
  end

  @impl true
  def handle_info(
        {port, {:exit_status, code}},
        %{port: port, caller: caller, buffer: buffer} = state
      ) do
    error = parse_error(buffer, code)
    GenServer.reply(caller, {:error, error})
    {:noreply, reset_state(state)}
  end

  # Private Helpers

  defp default_output_path(input_path) do
    base = Path.rootname(input_path)
    ext = Path.extname(input_path)
    "#{base}_warped#{ext}"
  end

  defp find_python do
    case System.find_executable("python3") || System.find_executable("python") do
      nil -> {:error, :python_not_found}
      python -> {:ok, python}
    end
  end

  defp find_script do
    script_path = Path.join(:code.priv_dir(:sound_forge), "python/audio_warp.py")

    if File.exists?(script_path) do
      {:ok, script_path}
    else
      {:error, {:script_not_found, script_path}}
    end
  end

  defp open_port(python, script, input_path, output_path, tempo_factor, pitch_semitones) do
    args = [
      script,
      input_path,
      output_path,
      "--tempo-factor",
      to_string(tempo_factor),
      "--pitch-semitones",
      to_string(pitch_semitones)
    ]

    Logger.debug("Opening audio_warp port: #{python} #{Enum.join(args, " ")}")

    Port.open({:spawn_executable, python}, [
      :binary,
      :exit_status,
      args: args
    ])
  end

  defp parse_output(buffer) do
    trimmed = String.trim(buffer)

    case Jason.decode(trimmed) do
      {:ok, %{"success" => true} = result} ->
        {:ok, result}

      {:ok, result} when is_map(result) ->
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
