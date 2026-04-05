defmodule SoundForge.ControlSurface.ActionBus do
  @moduledoc """
  Tab-context-aware routing bus for control surface actions.

  The `Mapping` schema stores a `tab_context` field ("dj", "daw",
  "library", "sampler") but `ActionExecutor` previously ignored it —
  so MIDI actions would fire globally regardless of the active tab.

  ActionBus maintains the currently-active tab and enriches every
  dispatched action with that context before broadcasting. Actions whose
  `tab_context` doesn't match the active tab are suppressed.

  ## PubSub topic

      "control_surface:actions"

  ## Broadcast payload

      {:action, action :: atom(), params :: map()}

  `params` always includes a `:tab_context` key set to the active tab.

  ## Usage

      # Called from DashboardLive when the user switches tabs
      ActionBus.set_active_tab("dj")

      # Called from ActionExecutor instead of direct PubSub broadcast
      ActionBus.dispatch(:set_volume, %{deck: 1, value: 0.8}, "dj")
  """

  use GenServer

  alias Phoenix.PubSub

  @topic "control_surface:actions"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Notify the bus which tab is currently active."
  def set_active_tab(tab) when is_binary(tab) do
    if pid = Process.whereis(__MODULE__) do
      GenServer.cast(pid, {:set_active_tab, tab})
    end

    :ok
  end

  @doc "Return the currently-active tab name."
  def active_tab do
    case Process.whereis(__MODULE__) do
      nil -> "library"
      pid -> GenServer.call(pid, :active_tab)
    end
  end

  @doc """
  Dispatch an action through the bus.

  `mapping_tab_context` is the `tab_context` stored on the Mapping record
  (nil or "" means fire in any tab). Returns `:fired` or `:suppressed`.
  """
  def dispatch(action, params, mapping_tab_context \\ nil) do
    case Process.whereis(__MODULE__) do
      nil ->
        # Bus not started — fire unconditionally (graceful degradation)
        PubSub.broadcast(SoundForge.PubSub, @topic, {:action, action, params})
        :fired

      pid ->
        GenServer.call(pid, {:dispatch, action, params, mapping_tab_context})
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{active_tab: "library"}}
  end

  @impl true
  def handle_cast({:set_active_tab, tab}, state) do
    {:noreply, %{state | active_tab: tab}}
  end

  @impl true
  def handle_call(:active_tab, _from, state) do
    {:reply, state.active_tab, state}
  end

  @impl true
  def handle_call({:dispatch, action, params, ctx}, _from, state) do
    if should_fire?(ctx, state.active_tab) do
      enriched = Map.put(params, :tab_context, state.active_tab)
      PubSub.broadcast(SoundForge.PubSub, @topic, {:action, action, enriched})
      {:reply, :fired, state}
    else
      {:reply, :suppressed, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # nil or "" context means "fire in any tab"
  defp should_fire?(nil, _active), do: true
  defp should_fire?("", _active), do: true
  defp should_fire?(ctx, active), do: ctx == active
end
