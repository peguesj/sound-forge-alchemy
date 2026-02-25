defmodule SoundForge.Agents.Orchestrator do
  @moduledoc """
  Workflow orchestrator that routes tasks to the appropriate specialist agent
  and manages multi-agent pipelines.

  The Orchestrator is the single entry point for all agentic work in SFA.
  It:

  1. Inspects the incoming `Context.instruction` and optional `:task` hint
  2. Selects the best specialist agent (or a pipeline of agents) for the work
  3. Executes the agent(s) sequentially or in parallel as needed
  4. Merges and returns a unified `Result`

  ## Direct dispatch

      Orchestrator.run(%Context{instruction: "Analyse the key", track_id: id}, task: :track_analysis)

  ## Auto-routing (no task hint)

      Orchestrator.run(%Context{instruction: "Plan a set with these 5 tracks", track_ids: ids})

  ## Pipeline execution

      Orchestrator.pipeline(%Context{...}, [TrackAnalysisAgent, MixPlanningAgent])
  """

  require Logger

  alias SoundForge.Agents.{Context, Result}

  # Capability → agent module mapping.
  # Ordered by specificity; the first match wins for auto-routing.
  @capability_map [
    {:track_analysis, SoundForge.Agents.TrackAnalysisAgent},
    {:key_detection, SoundForge.Agents.TrackAnalysisAgent},
    {:bpm_detection, SoundForge.Agents.TrackAnalysisAgent},
    {:energy_analysis, SoundForge.Agents.TrackAnalysisAgent},
    {:harmonic_analysis, SoundForge.Agents.TrackAnalysisAgent},
    {:mix_planning, SoundForge.Agents.MixPlanningAgent},
    {:track_sequencing, SoundForge.Agents.MixPlanningAgent},
    {:transition_advice, SoundForge.Agents.MixPlanningAgent},
    {:key_compatibility, SoundForge.Agents.MixPlanningAgent},
    {:stem_analysis, SoundForge.Agents.StemIntelligenceAgent},
    {:stem_recommendations, SoundForge.Agents.StemIntelligenceAgent},
    {:loop_extraction_advice, SoundForge.Agents.StemIntelligenceAgent},
    {:cue_point_analysis, SoundForge.Agents.CuePointAgent},
    {:loop_region_detection, SoundForge.Agents.CuePointAgent},
    {:drop_detection, SoundForge.Agents.CuePointAgent},
    {:mastering_advice, SoundForge.Agents.MasteringAgent},
    {:loudness_analysis, SoundForge.Agents.MasteringAgent},
    {:library_search, SoundForge.Agents.LibraryAgent},
    {:track_recommendations, SoundForge.Agents.LibraryAgent},
    {:playlist_curation, SoundForge.Agents.LibraryAgent}
  ]

  # Keyword patterns used for instruction-based auto-routing when no :task hint.
  @instruction_patterns [
    {~r/\b(analys|key|bpm|tempo|chord|harmonic|genre)\b/i, SoundForge.Agents.TrackAnalysisAgent},
    {~r/\b(mix|set|playlist|transition|sequence|order)\b/i, SoundForge.Agents.MixPlanningAgent},
    {~r/\b(stem|vocal|drum|bass|isolat)\b/i, SoundForge.Agents.StemIntelligenceAgent},
    {~r/\b(cue|loop|drop|phrase|marker)\b/i, SoundForge.Agents.CuePointAgent},
    {~r/\b(master|loud|lufs|dynamic|eq|compress)\b/i, SoundForge.Agents.MasteringAgent},
    {~r/\b(librar|recommend|find|search|similar|tag|genre)\b/i, SoundForge.Agents.LibraryAgent}
  ]

  @doc """
  Runs the orchestrator: selects the best agent and executes it.

  ## Options
  - `:task` - atom capability hint (e.g. `:track_analysis`) for direct dispatch
  - Any other opts are forwarded to the selected agent's `run/2`

  Returns `{:ok, %Result{}}` or `{:error, reason}`.
  """
  @spec run(Context.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def run(%Context{} = ctx, opts \\ []) do
    agent_module = select_agent(ctx, opts)
    task_opts = Keyword.delete(opts, :task)

    Logger.debug("[Orchestrator] dispatching to #{inspect(agent_module)}: #{ctx.instruction}")

    agent_module.run(ctx, task_opts)
  rescue
    error ->
      reason = Exception.message(error)
      Logger.error("[Orchestrator] agent error: #{reason}")
      {:error, reason}
  end

  @doc """
  Runs a sequential pipeline of agent modules, passing each result's data
  into the next agent's context.

  The first agent receives `ctx` unchanged.  Subsequent agents receive `ctx`
  with `:data` merged from the previous result's `:data`.

  Returns `{:ok, [%Result{}]}` with all results, or `{:error, reason}` on the
  first failure.
  """
  @spec pipeline(Context.t(), [module()], keyword()) ::
          {:ok, [Result.t()]} | {:error, term()}
  def pipeline(%Context{} = ctx, agents, opts \\ []) when is_list(agents) do
    agents
    |> Enum.reduce_while({:ok, {ctx, []}}, fn agent_module, {:ok, {current_ctx, results}} ->
      case agent_module.run(current_ctx, opts) do
        {:ok, %Result{} = result} ->
          updated_ctx = merge_result_into_context(current_ctx, result)
          {:cont, {:ok, {updated_ctx, results ++ [result]}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, {_final_ctx, results}} -> {:ok, results}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the agent module that would be selected for the given context and opts,
  without executing it.  Useful for UI previews and testing.
  """
  @spec select_agent(Context.t(), keyword()) :: module()
  def select_agent(%Context{} = ctx, opts) do
    cond do
      task = Keyword.get(opts, :task) ->
        agent_for_capability(task) || default_agent()

      true ->
        agent_for_instruction(ctx.instruction) || default_agent()
    end
  end

  @doc "Returns the registered capability → agent module mapping."
  @spec capability_map() :: [{atom(), module()}]
  def capability_map, do: @capability_map

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp agent_for_capability(capability) when is_atom(capability) do
    case List.keyfind(@capability_map, capability, 0) do
      {^capability, module} -> module
      nil -> nil
    end
  end

  defp agent_for_instruction(instruction) when is_binary(instruction) do
    Enum.find_value(@instruction_patterns, fn {pattern, module} ->
      if Regex.match?(pattern, instruction), do: module
    end)
  end

  defp default_agent, do: SoundForge.Agents.TrackAnalysisAgent

  defp merge_result_into_context(ctx, %Result{data: nil}), do: ctx

  defp merge_result_into_context(%Context{data: nil} = ctx, %Result{data: data})
       when is_map(data) do
    %{ctx | data: data}
  end

  defp merge_result_into_context(%Context{data: existing} = ctx, %Result{data: incoming})
       when is_map(existing) and is_map(incoming) do
    %{ctx | data: Map.merge(existing, incoming)}
  end

  defp merge_result_into_context(ctx, _result), do: ctx
end
