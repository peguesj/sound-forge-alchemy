defmodule SoundForge.Workflow.ImportWizardSteps do
  @moduledoc """
  Concrete step pipeline for the SFA track import wizard, built on
  `SoundForge.Workflow.Steps`.

  Base flow:

      source_select -> metadata -> stem_config -> [separation_engine] ->
      analysis_opts -> review -> submit

  `separation_engine` only appears when the state's stem config requests a
  non-default engine (`engine: :lalalai` or `engine: :custom`), mirroring the
  conditional `illumination`/`dimensions` steps in the vyynl job flow.

  State keys read: `:stems_enabled` (boolean, default true — when false the
  `stem_config` and `separation_engine` steps drop out) and `:engine`.
  """

  alias SoundForge.Workflow.Steps

  @type state :: Steps.state()

  @spec spec() :: Steps.spec()
  def spec do
    [
      {:source_select, true},
      {:metadata, true},
      {:stem_config, &stems_enabled?/1},
      {:separation_engine, fn state -> stems_enabled?(state) and non_default_engine?(state) end},
      {:analysis_opts, true},
      {:review, true},
      {:submit, true}
    ]
  end

  @spec active_steps(state()) :: [Steps.step_id()]
  def active_steps(state), do: Steps.active_steps(spec(), state)

  @spec step_index(state(), Steps.step_id()) :: pos_integer() | nil
  def step_index(state, step_id), do: Steps.step_index(spec(), state, step_id)

  @spec total_steps(state()) :: non_neg_integer()
  def total_steps(state), do: Steps.total_steps(spec(), state)

  @spec progress(state(), Steps.step_id()) :: float()
  def progress(state, step_id), do: Steps.progress(spec(), state, step_id)

  defp stems_enabled?(state), do: Map.get(state, :stems_enabled, true)

  defp non_default_engine?(state), do: Map.get(state, :engine) in [:lalalai, :custom]
end
