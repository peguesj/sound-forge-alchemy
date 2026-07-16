defmodule SoundForge.Workflow.OrchestratorTest do
  use ExUnit.Case, async: true

  alias SoundForge.Workflow.Orchestrator

  # No real sleeping in tests: record requested delays instead.
  defp capture_sleep(pid), do: fn ms -> send(pid, {:slept, ms}) end

  defp attach_telemetry(test_name) do
    pid = self()

    events =
      for stage <- [:idempotency, :guard, :work, :validate, :persist],
          do: [:sound_forge, :workflow, stage]

    :telemetry.attach_many(
      to_string(test_name),
      events,
      fn event, measurements, metadata, _ ->
        send(pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(to_string(test_name)) end)
  end

  test "happy path runs all stages and returns persisted result", %{test: test_name} do
    attach_telemetry(test_name)

    assert {:ok, {:persisted, 42}} =
             Orchestrator.run(21,
               idempotency: fn 21 -> :miss end,
               guard: fn 21 -> :ok end,
               work: fn n -> {:ok, n * 2} end,
               validate: fn 42 -> :ok end,
               persist: fn 42 -> {:ok, {:persisted, 42}} end
             )

    assert_received {:telemetry, [:sound_forge, :workflow, :idempotency], _, %{outcome: :miss}}
    assert_received {:telemetry, [:sound_forge, :workflow, :guard], _, %{outcome: :ok}}
    assert_received {:telemetry, [:sound_forge, :workflow, :work], %{attempt: 1}, %{outcome: :ok}}
    assert_received {:telemetry, [:sound_forge, :workflow, :validate], _, %{outcome: :ok}}
    assert_received {:telemetry, [:sound_forge, :workflow, :persist], _, %{outcome: :ok}}
  end

  test "idempotency hit short-circuits without running work" do
    assert {:ok, :cached} =
             Orchestrator.run(:input,
               idempotency: fn :input -> {:hit, :cached} end,
               work: fn _ -> flunk("work must not run on idempotency hit") end
             )
  end

  test "guard block returns {:error, :guard, reason} and skips work", %{test: test_name} do
    attach_telemetry(test_name)

    assert {:error, :guard, :quota_exceeded} =
             Orchestrator.run(:input,
               guard: fn _ -> {:error, :quota_exceeded} end,
               work: fn _ -> flunk("work must not run when guard blocks") end
             )

    assert_received {:telemetry, [:sound_forge, :workflow, :guard], _,
                     %{outcome: :blocked, reason: :quota_exceeded}}
  end

  test "work retries with [500, 2000, 5000] backoff then succeeds" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    work = fn _ ->
      attempt = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      if attempt < 3, do: {:error, :flaky}, else: {:ok, :done}
    end

    assert {:ok, :done} = Orchestrator.run(:input, work: work, sleep: capture_sleep(self()))

    assert_received {:slept, 500}
    assert_received {:slept, 2000}
    refute_received {:slept, 5000}
    assert Agent.get(agent, & &1) == 3
  end

  test "exhausted retries return {:error, :work, reason} after 4 attempts" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    work = fn _ ->
      Agent.update(agent, &(&1 + 1))
      {:error, :always_down}
    end

    assert {:error, :work, :always_down} =
             Orchestrator.run(:input, work: work, sleep: capture_sleep(self()))

    # initial attempt + one per backoff entry
    assert Agent.get(agent, & &1) == 4
    assert_received {:slept, 500}
    assert_received {:slept, 2000}
    assert_received {:slept, 5000}
  end

  test "retryable?/1 false stops retries immediately" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    work = fn _ ->
      Agent.update(agent, &(&1 + 1))
      {:error, :bad_request}
    end

    assert {:error, :work, :bad_request} =
             Orchestrator.run(:input,
               work: work,
               retryable?: fn reason -> reason != :bad_request end,
               sleep: capture_sleep(self())
             )

    assert Agent.get(agent, & &1) == 1
    refute_received {:slept, _}
  end

  test "validate failure returns {:error, :validate, reason} and skips persist" do
    assert {:error, :validate, :corrupt_output} =
             Orchestrator.run(:input,
               work: fn _ -> {:ok, :raw} end,
               validate: fn :raw -> {:error, :corrupt_output} end,
               persist: fn _ -> flunk("persist must not run on validate failure") end
             )
  end

  test "persist failure returns {:error, :persist, reason}" do
    assert {:error, :persist, :disk_full} =
             Orchestrator.run(:input,
               work: fn _ -> {:ok, :raw} end,
               persist: fn :raw -> {:error, :disk_full} end
             )
  end

  test "optional stages default: only work is required" do
    assert {:ok, :result} = Orchestrator.run(:input, work: fn _ -> {:ok, :result} end)
  end

  test "custom retry_backoff and telemetry_metadata are honored", %{test: test_name} do
    attach_telemetry(test_name)
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    work = fn _ ->
      attempt = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      if attempt == 1, do: {:error, :once}, else: {:ok, :ok_now}
    end

    assert {:ok, :ok_now} =
             Orchestrator.run(:input,
               work: work,
               retry_backoff: [10],
               sleep: capture_sleep(self()),
               telemetry_metadata: %{pipeline: :test_pipeline}
             )

    assert_received {:slept, 10}

    assert_received {:telemetry, [:sound_forge, :workflow, :work], %{attempt: 1},
                     %{outcome: :error, reason: :once, pipeline: :test_pipeline}}

    assert_received {:telemetry, [:sound_forge, :workflow, :work], %{attempt: 2},
                     %{outcome: :ok, pipeline: :test_pipeline}}
  end
end
