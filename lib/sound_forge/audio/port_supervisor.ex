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
end
