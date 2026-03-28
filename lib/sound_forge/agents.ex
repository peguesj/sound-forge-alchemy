defmodule SoundForge.Agents do
  @moduledoc """
  Public API for the platform agent system.

  ## Available agents

    - `"agent-sonic-analyst"` — BPM/key/energy profiling + mix compatibility scoring
  """

  alias SoundForge.Agents.{AgentRegistry, AgentRunner}

  @doc """
  Trigger an agent by ID with a payload.

  Returns `{:ok, execution_id}` immediately. Subscribe to
  `"agents:{agent_id}"` PubSub topic to receive the result.

  ## Example

      {:ok, exec_id} = SoundForge.Agents.trigger("agent-sonic-analyst", %{
        track_ids: [track_id_1, track_id_2],
        user_id: current_user.id
      })
  """
  @spec trigger(String.t(), map()) :: {:ok, String.t()} | {:error, :agent_not_found}
  defdelegate trigger(agent_id, payload), to: AgentRunner

  @doc "Retrieve a stored agent output by execution ID."
  @spec get_output(String.t(), String.t()) :: map() | nil
  defdelegate get_output(agent_id, execution_id), to: AgentRegistry

  @doc "List recent outputs for an agent."
  @spec list_outputs(String.t(), non_neg_integer()) :: [map()]
  defdelegate list_outputs(agent_id, limit \\ 20), to: AgentRegistry
end
