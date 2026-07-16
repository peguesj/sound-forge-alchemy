defmodule SoundForge.LiveHarness.StateTest do
  use ExUnit.Case, async: true

  alias SoundForge.LiveHarness.State

  defp result(status), do: %{id: "s", status: status}

  describe "derive/2" do
    test "nil summary is :idle with all phases pending" do
      state = State.derive(nil)
      assert state.status == :idle
      assert Enum.map(state.phases, & &1.id) == ["scan", "correlate", "github", "fix"]
      assert Enum.all?(state.phases, &(&1.status == :pending))
      assert state.coverage.total == 0
    end

    test "stale summary is :awaiting_fresh_run" do
      state = State.derive(%{run_id: "r1", results: [result(:pass)]}, fresh: false)
      assert state.status == :awaiting_fresh_run
      assert Enum.find(state.phases, &(&1.id == "scan")).status == :warn
    end

    test "failures yield :awaiting_fix with fix phase running" do
      state = State.derive(%{run_id: "r1", results: [result(:pass), result(:fail)]})
      assert state.status == :awaiting_fix
      assert Enum.find(state.phases, &(&1.id == "fix")).status == :running
    end

    test "blocked steps also yield :awaiting_fix" do
      state = State.derive(%{run_id: "r1", results: [result(:blocked)]})
      assert state.status == :awaiting_fix
    end

    test "all passing yields :complete" do
      state = State.derive(%{run_id: "r1", results: [result(:pass), result(:warn)]})
      assert state.status == :complete
      assert Enum.all?(state.phases, &(&1.status == :pass))
    end

    test "accepts string keys from decoded JSON" do
      state = State.derive(%{"run_id" => "r1", "results" => [%{"status" => "fail"}]})
      assert state.status == :awaiting_fix
    end
  end

  describe "summarize_coverage/1" do
    test "empty results" do
      assert State.summarize_coverage([]) ==
               %{total: 0, pass: 0, warn: 0, fail: 0, blocked: 0, pass_rate: 0.0}
    end

    test "counts each status and computes pass rate" do
      coverage =
        State.summarize_coverage([
          result(:pass),
          result(:pass),
          result(:warn),
          result(:fail)
        ])

      assert coverage.total == 4
      assert coverage.pass == 2
      assert coverage.warn == 1
      assert coverage.fail == 1
      assert coverage.blocked == 0
      assert coverage.pass_rate == 0.5
    end

    test "unknown statuses count as blocked" do
      assert State.summarize_coverage([result(:mystery)]).blocked == 1
    end
  end
end
