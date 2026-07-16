defmodule SoundForge.Workflow.Lifecycle do
  @moduledoc """
  Generic finite-state-machine helper for status lifecycles.

  Ported from vyynl-sales-web `lib/consult-flow/lifecycle.ts` (explicit
  `ALLOWED_TRANSITIONS` map + `canTransitionConsultSession`), generalized so any
  SFA subsystem can declare a transitions map and get validated transitions.

  Two ways to use it:

  1. Directly with a transitions map:

         transitions = %{queued: [:queued, :downloading], downloading: [:downloading, :completed]}
         Lifecycle.can_transition?(transitions, :queued, :downloading) #=> true
         Lifecycle.transition(transitions, :queued, :downloading)     #=> {:ok, :downloading}

  2. Via `use SoundForge.Workflow.Lifecycle, transitions: %{...}` which compiles
     the map in and exposes `statuses/0`, `valid_status?/1`, `can_transition?/2`,
     and `transition/2` on the using module. See
     `SoundForge.Workflow.ProcessingLifecycle` for a concrete example mirroring
     the SFA track pipeline.

  A transitions map is `%{status => [allowed_next_status]}`. As in the source
  TypeScript, self-transitions are only allowed when explicitly listed.
  """

  @type status :: atom()
  @type transitions :: %{status() => [status()]}

  @doc """
  Returns true when `to` is an allowed next status from `from`.

  Unknown `from` statuses return false (no raise), matching the tagged-tuple
  error philosophy of SFA contexts.
  """
  @spec can_transition?(transitions(), status(), status()) :: boolean()
  def can_transition?(transitions, from, to) when is_map(transitions) do
    to in Map.get(transitions, from, [])
  end

  @doc """
  Validated transition. Returns `{:ok, to}` when allowed, otherwise
  `{:error, :invalid_transition}`.
  """
  @spec transition(transitions(), status(), status()) ::
          {:ok, status()} | {:error, :invalid_transition}
  def transition(transitions, from, to) do
    if can_transition?(transitions, from, to) do
      {:ok, to}
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  All statuses appearing in the transitions map (keys plus reachable targets).
  """
  @spec statuses(transitions()) :: [status()]
  def statuses(transitions) do
    transitions
    |> Enum.flat_map(fn {from, tos} -> [from | tos] end)
    |> Enum.uniq()
  end

  @doc """
  Statuses with no outgoing transitions other than (optionally) themselves.
  Analogous to `promoted`/`abandoned` in the source FSM.
  """
  @spec terminal_statuses(transitions()) :: [status()]
  def terminal_statuses(transitions) do
    transitions
    |> statuses()
    |> Enum.filter(fn s ->
      Map.get(transitions, s, []) -- [s] == []
    end)
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @lifecycle_transitions Keyword.fetch!(opts, :transitions)

      @doc "The compiled transitions map for this lifecycle."
      @spec transitions() :: SoundForge.Workflow.Lifecycle.transitions()
      def transitions, do: @lifecycle_transitions

      @doc "All known statuses in this lifecycle."
      @spec statuses() :: [atom()]
      def statuses, do: SoundForge.Workflow.Lifecycle.statuses(@lifecycle_transitions)

      @doc "True when the value is a known status atom."
      @spec valid_status?(term()) :: boolean()
      def valid_status?(value), do: value in statuses()

      @doc "True when `to` is an allowed next status from `from`."
      @spec can_transition?(atom(), atom()) :: boolean()
      def can_transition?(from, to),
        do: SoundForge.Workflow.Lifecycle.can_transition?(@lifecycle_transitions, from, to)

      @doc "Validated transition: `{:ok, to}` or `{:error, :invalid_transition}`."
      @spec transition(atom(), atom()) :: {:ok, atom()} | {:error, :invalid_transition}
      def transition(from, to),
        do: SoundForge.Workflow.Lifecycle.transition(@lifecycle_transitions, from, to)

      @doc "Terminal statuses of this lifecycle."
      @spec terminal_statuses() :: [atom()]
      def terminal_statuses,
        do: SoundForge.Workflow.Lifecycle.terminal_statuses(@lifecycle_transitions)
    end
  end
end
