defmodule SoundForge.Agents.AgentRegistry do
  @moduledoc """
  ETS-backed store for agent outputs.

  Agents write their results here after completing a task. Results can be
  retrieved by `(agent_id, execution_id)` or listed by `agent_id`.

  ## Usage

      # Store an output
      AgentRegistry.store_output("agent-sonic-analyst", "exec-abc123", %{score: 0.87})

      # Retrieve a specific output
      AgentRegistry.get_output("agent-sonic-analyst", "exec-abc123")
      # => %{score: 0.87}

      # List all outputs for an agent (newest first)
      AgentRegistry.list_outputs("agent-sonic-analyst")
  """

  use GenServer

  @table :sfa_agent_outputs
  @max_per_agent 50

  # -- Public API --

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Store an agent output by (agent_id, execution_id)."
  @spec store_output(String.t(), String.t(), term()) :: :ok
  def store_output(agent_id, execution_id, result) do
    if table_exists?() do
      ts = System.monotonic_time(:microsecond)
      entry = %{agent_id: agent_id, execution_id: execution_id, result: result, stored_at: ts}
      :ets.insert(@table, {{agent_id, execution_id}, entry})
      prune_agent_outputs(agent_id)
    end

    :ok
  end

  @doc "Retrieve an output for a given (agent_id, execution_id). Returns nil if not found."
  @spec get_output(String.t(), String.t()) :: map() | nil
  def get_output(agent_id, execution_id) do
    if table_exists?() do
      case :ets.lookup(@table, {agent_id, execution_id}) do
        [{_, entry}] -> entry
        [] -> nil
      end
    end
  end

  @doc "List all outputs for an agent, newest first (by storage time)."
  @spec list_outputs(String.t(), non_neg_integer()) :: [map()]
  def list_outputs(agent_id, limit \\ 20) do
    if not table_exists?(), do: throw(:no_table)

    match_spec = [{{{agent_id, :"$1"}, :"$2"}, [], [:"$2"]}]

    @table
    |> :ets.select(match_spec)
    |> Enum.sort_by(& &1.stored_at, :desc)
    |> Enum.take(limit)
  catch
    :no_table -> []
  end

  # -- GenServer --

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # -- Private --

  defp table_exists? do
    :ets.whereis(@table) != :undefined
  end

  defp prune_agent_outputs(agent_id) do
    match_spec = [{{{agent_id, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}]
    entries = :ets.select(@table, match_spec)

    if length(entries) > @max_per_agent do
      entries
      |> Enum.sort_by(fn {_exec_id, entry} -> entry.stored_at end, :asc)
      |> Enum.take(length(entries) - @max_per_agent)
      |> Enum.each(fn {exec_id, _} -> :ets.delete(@table, {agent_id, exec_id}) end)
    end
  end
end
