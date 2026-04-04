defmodule SoundForge.Agents.AgentRunner do
  @moduledoc """
  GenServer that manages the lifecycle of platform AI agents.

  Agents are registered by ID and triggered via `SoundForge.Agents.trigger/2`.
  Each trigger spawns an async Task under `SoundForge.TaskSupervisor`. Outputs
  are persisted to `AgentRegistry` and broadcast on `"agents:{agent_id}"` PubSub
  topic so LiveViews can stream results.

  ## Trigger

      SoundForge.Agents.trigger("agent-sonic-analyst", %{
        track_ids: ["uuid1", "uuid2"],
        user_id: 42
      })

  ## Subscribe to results

      Phoenix.PubSub.subscribe(SoundForge.PubSub, "agents:agent-sonic-analyst")

      def handle_info({:agent_output, output}, socket) do
        # output.result contains the agent's return value
        ...
      end
  """

  use GenServer

  alias SoundForge.Agents.{AgentRegistry, Context}

  require Logger

  @registry_name :sfa_agent_modules

  # -- Public API --

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Trigger an agent by its ID with a payload map.

  The agent module must be registered (done automatically for built-in agents).
  Returns `{:ok, execution_id}` immediately — the agent runs async.
  """
  @spec trigger(String.t(), map()) :: {:ok, String.t()} | {:error, :agent_not_found}
  def trigger(agent_id, payload) do
    GenServer.call(__MODULE__, {:trigger, agent_id, payload})
  end

  @doc "Register an agent module under an ID."
  @spec register(String.t(), module()) :: :ok
  def register(agent_id, module) do
    GenServer.call(__MODULE__, {:register, agent_id, module})
  end

  @doc "List all registered agent IDs."
  @spec list_agents() :: [String.t()]
  def list_agents do
    :ets.tab2list(@registry_name) |> Enum.map(fn {id, _mod} -> id end)
  end

  # -- GenServer --

  @impl true
  def init(_opts) do
    table = :ets.new(@registry_name, [:named_table, :set, :public])
    register_builtin_agents(table)

    # Subscribe to PubSub events that trigger agents
    Phoenix.PubSub.subscribe(SoundForge.PubSub, "agent_triggers")

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:trigger, agent_id, payload}, _from, state) do
    case :ets.lookup(@registry_name, agent_id) do
      [{^agent_id, module}] ->
        execution_id = Ecto.UUID.generate()
        spawn_agent_task(agent_id, module, execution_id, payload)
        {:reply, {:ok, execution_id}, state}

      [] ->
        {:reply, {:error, :agent_not_found}, state}
    end
  end

  @impl true
  def handle_call({:register, agent_id, module}, _from, state) do
    :ets.insert(@registry_name, {agent_id, module})
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:trigger_event, agent_id, payload}, state) do
    case :ets.lookup(@registry_name, agent_id) do
      [{^agent_id, module}] ->
        execution_id = Ecto.UUID.generate()
        spawn_agent_task(agent_id, module, execution_id, payload)

      [] ->
        Logger.debug("AgentRunner: received trigger for unregistered agent #{agent_id}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # -- Private --

  defp register_builtin_agents(table) do
    :ets.insert(table, {"agent-sonic-analyst", SoundForge.Agents.SonicAnalyst})
    :ets.insert(table, {"agent-crate-analyst", SoundForge.Agents.CrateAnalyst})
  end

  defp spawn_agent_task(agent_id, module, execution_id, payload) do
    Task.Supervisor.start_child(SoundForge.TaskSupervisor, fn ->
      Logger.info("AgentRunner: starting #{agent_id} (#{execution_id})")

      ctx = %Context{
        instruction: payload[:instruction] || payload["instruction"] || "run",
        user_id: payload[:user_id] || payload["user_id"],
        track_id: payload[:track_id] || payload["track_id"],
        track_ids: payload[:track_ids] || payload["track_ids"],
        data: Map.drop(payload, [:instruction, :user_id, :track_id, :track_ids,
                                  "instruction", "user_id", "track_id", "track_ids"])
      }

      result =
        try do
          module.run(ctx, %{agent_id: agent_id, execution_id: execution_id})
        rescue
          e ->
            Logger.error("AgentRunner: agent #{agent_id} crashed — #{inspect(e)}")
            {:error, :agent_crashed}
        end

      AgentRegistry.store_output(agent_id, execution_id, result)

      Phoenix.PubSub.broadcast(
        SoundForge.PubSub,
        "agents:#{agent_id}",
        {:agent_output, %{agent_id: agent_id, execution_id: execution_id, result: result}}
      )

      Logger.info("AgentRunner: #{agent_id} (#{execution_id}) complete")
    end)
  end
end
