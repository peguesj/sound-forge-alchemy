defmodule SoundForge.Audio.AudioToMidiPort do
  @moduledoc """
  Erlang Port wrapper for basic-pitch audio-to-MIDI conversion.

  Provides supervised Port communication with the Python audio_to_midi script
  for converting audio files to MIDI note data.

  ## Usage

      {:ok, pid} = AudioToMidiPort.start_link()
      {:ok, notes} = AudioToMidiPort.convert("/path/to/audio.mp3")
  """

  use GenServer
  require Logger

  @default_timeout 180_000

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
  Converts an audio file to MIDI note data.

  Returns `{:ok, notes}` where notes is a list of maps with :note, :onset, :offset, :velocity, :confidence.
  """
  def convert(audio_path, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:convert, audio_path}, @default_timeout)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{port: nil, caller: nil, buffer: ""}}
  end

  @impl true
  def handle_call({:convert, audio_path}, from, state) do
    case find_python() do
      {:ok, python} ->
        case find_script() do
          {:ok, script} ->
            port = open_port(python, script, audio_path)
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

  defp find_python do
    case System.find_executable("python3") || System.find_executable("python") do
      nil -> {:error, :python_not_found}
      python -> {:ok, python}
    end
  end

  defp find_script do
    script_path = Path.join(:code.priv_dir(:sound_forge), "python/audio_to_midi.py")

    if File.exists?(script_path) do
      {:ok, script_path}
    else
      {:error, {:script_not_found, script_path}}
    end
  end

  defp open_port(python, script, audio_path) do
    Logger.debug("Opening audio_to_midi port: #{python} #{script} #{audio_path}")

    Port.open({:spawn_executable, python}, [
      :binary,
      :exit_status,
      args: [script, audio_path]
    ])
  end

  defp parse_output(buffer) do
    trimmed = String.trim(buffer)

    case Jason.decode(trimmed) do
      {:ok, notes} when is_list(notes) ->
        {:ok, notes}

      {:ok, _other} ->
        {:error, {:unexpected_output, trimmed}}

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
