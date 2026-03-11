defmodule SoundForge.Audio.PortSupervisor do
  @moduledoc """
  DynamicSupervisor for audio processing port processes.

  Allows workers to spawn individual DemucsPort and AnalyzerPort GenServer
  instances on demand, avoiding singleton bottleneck.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a DemucsPort process under this supervisor.
  Returns `{:ok, pid}`.
  """
  def start_demucs do
    spec = %{
      id: make_ref(),
      start: {SoundForge.Audio.DemucsPort, :start_link, [[]]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Starts an AnalyzerPort process under this supervisor.
  Returns `{:ok, pid}`.
  """
  def start_analyzer do
    spec = %{
      id: make_ref(),
      start: {SoundForge.Audio.AnalyzerPort, :start_link, [[]]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Starts an AudioToMidiPort process under this supervisor.
  Returns `{:ok, pid}`.
  """
  def start_audio_to_midi do
    spec = %{
      id: make_ref(),
      start: {SoundForge.Audio.AudioToMidiPort, :start_link, [[]]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Starts a ChordDetectorPort process under this supervisor.
  Returns `{:ok, pid}`.
  """
  def start_chord_detector do
    spec = %{
      id: make_ref(),
      start: {SoundForge.Audio.ChordDetectorPort, :start_link, [[]]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Starts an AudioWarpPort process under this supervisor.
  Returns `{:ok, pid}`.
  """
  def start_audio_warp do
    spec = %{
      id: make_ref(),
      start: {SoundForge.Audio.AudioWarpPort, :start_link, [[]]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
