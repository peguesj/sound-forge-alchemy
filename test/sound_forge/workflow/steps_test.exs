defmodule SoundForge.Workflow.StepsTest do
  use ExUnit.Case, async: true

  alias SoundForge.Workflow.Steps
  alias SoundForge.Workflow.ImportWizardSteps

  defp spec_fixture,
    do: [
      {:a, true},
      {:b, fn state -> state[:want_b] == true end},
      {:c, true},
      {:d, fn state -> Map.get(state, :count, 0) > 2 end}
    ]

  describe "active_steps/2" do
    test "includes unconditional steps only for empty state" do
      assert Steps.active_steps(spec_fixture(), %{}) == [:a, :c]
    end

    test "conditional steps appear when predicates hold, order preserved" do
      assert Steps.active_steps(spec_fixture(), %{want_b: true, count: 5}) == [:a, :b, :c, :d]
    end
  end

  describe "step_index/3" do
    test "1-based index within the active list" do
      assert Steps.step_index(spec_fixture(), %{want_b: true}, :c) == 3
      assert Steps.step_index(spec_fixture(), %{}, :c) == 2
    end

    test "nil for inactive step" do
      assert Steps.step_index(spec_fixture(), %{}, :b) == nil
    end
  end

  describe "total_steps/2 and progress/3" do
    test "total reflects state" do
      assert Steps.total_steps(spec_fixture(), %{}) == 2
      assert Steps.total_steps(spec_fixture(), %{want_b: true, count: 3}) == 4
    end

    test "progress fraction" do
      assert Steps.progress(spec_fixture(), %{want_b: true, count: 3}, :b) == 0.5
      assert Steps.progress(spec_fixture(), %{want_b: true, count: 3}, :d) == 1.0
      assert Steps.progress(spec_fixture(), %{}, :b) == 0.0
    end
  end

  describe "ImportWizardSteps" do
    test "default state includes stem_config but not separation_engine" do
      assert ImportWizardSteps.active_steps(%{}) ==
               [:source_select, :metadata, :stem_config, :analysis_opts, :review, :submit]
    end

    test "non-default engine adds separation_engine step" do
      for engine <- [:lalalai, :custom] do
        assert :separation_engine in ImportWizardSteps.active_steps(%{engine: engine})
      end

      assert ImportWizardSteps.active_steps(%{engine: :custom}) == [
               :source_select,
               :metadata,
               :stem_config,
               :separation_engine,
               :analysis_opts,
               :review,
               :submit
             ]
    end

    test "default engine (demucs) does not add separation_engine" do
      refute :separation_engine in ImportWizardSteps.active_steps(%{engine: :demucs})
    end

    test "stems disabled drops stem_config and separation_engine" do
      assert ImportWizardSteps.active_steps(%{stems_enabled: false, engine: :custom}) ==
               [:source_select, :metadata, :analysis_opts, :review, :submit]
    end

    test "step_index and total shift with conditional steps" do
      assert ImportWizardSteps.step_index(%{}, :review) == 5
      assert ImportWizardSteps.step_index(%{engine: :lalalai}, :review) == 6
      assert ImportWizardSteps.total_steps(%{}) == 6
      assert ImportWizardSteps.total_steps(%{engine: :lalalai}) == 7
    end

    test "progress at submit is 1.0 regardless of branch" do
      assert ImportWizardSteps.progress(%{}, :submit) == 1.0
      assert ImportWizardSteps.progress(%{engine: :custom}, :submit) == 1.0
    end
  end
end
