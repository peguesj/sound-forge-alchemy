defmodule SoundForge.Workflow.Steps do
  @moduledoc """
  Dynamic conditional step pipelines.

  Ported from vyynl-sales-web `lib/job-flow/steps.ts`
  (`getActiveSteps` / `getStepIndex` / `getTotalSteps`): a wizard's ordered step
  list is *derived* from partial state via per-step predicates, so conditional
  steps appear/disappear as earlier answers change. Pure functions, no I/O.

  A pipeline spec is an ordered list of `{step_id, predicate}` where the
  predicate is either `true` (always active) or a 1-arity function of the state
  map returning a boolean.

      spec = [
        {:source_select, true},
        {:separation_engine, fn state -> state[:engine] == :custom end},
        {:review, true}
      ]

      Steps.active_steps(spec, %{engine: :custom})
      #=> [:source_select, :separation_engine, :review]

  `SoundForge.Workflow.ImportWizardSteps` is the concrete SFA import wizard.
  """

  @type step_id :: atom()
  @type state :: map()
  @type predicate :: true | (state() -> boolean())
  @type spec :: [{step_id(), predicate()}]

  @doc """
  Ordered list of active step ids for the given state.
  """
  @spec active_steps(spec(), state()) :: [step_id()]
  def active_steps(spec, state) when is_list(spec) and is_map(state) do
    for {id, predicate} <- spec, active?(predicate, state), do: id
  end

  @doc """
  1-based index of `step_id` in the active list for this state, or `nil` if
  the step is not currently active (the TS source returned -1; `nil` is the
  Elixir-idiomatic sentinel).
  """
  @spec step_index(spec(), state(), step_id()) :: pos_integer() | nil
  def step_index(spec, state, step_id) do
    case Enum.find_index(active_steps(spec, state), &(&1 == step_id)) do
      nil -> nil
      i -> i + 1
    end
  end

  @doc """
  Number of active steps (denominator for progress).
  """
  @spec total_steps(spec(), state()) :: non_neg_integer()
  def total_steps(spec, state), do: length(active_steps(spec, state))

  @doc """
  Progress fraction (0.0..1.0) for the current step in the given state.
  Returns 0.0 when the step is not active.
  """
  @spec progress(spec(), state(), step_id()) :: float()
  def progress(spec, state, step_id) do
    case step_index(spec, state, step_id) do
      nil -> 0.0
      index -> index / total_steps(spec, state)
    end
  end

  defp active?(true, _state), do: true
  defp active?(predicate, state) when is_function(predicate, 1), do: !!predicate.(state)
end
