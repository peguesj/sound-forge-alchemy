defmodule SoundForge.ControlSurface.Supervisor do
  @moduledoc """
  DynamicSupervisor for all control surface adapters.

  Owns MIDI, OSC, and any future control protocol adapters
  (TouchOSC, Rekordbox, TSI). Adding a new protocol requires only a
  `start_adapter/2` call — no changes to Application.

  ## Usage

      # Start an adapter at runtime
      SoundForge.ControlSurface.Supervisor.start_adapter(
        SoundForge.ControlSurface.MidiAdapter,
        port: 0
      )

      # List running adapters
      SoundForge.ControlSurface.Supervisor.list_adapters()
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a control surface adapter as a child of this supervisor."
  def start_adapter(module, opts \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {module, opts})
  end

  @doc "List all currently running adapter child processes."
  def list_adapters do
    DynamicSupervisor.which_children(__MODULE__)
  end
end
