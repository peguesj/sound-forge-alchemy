defmodule SoundForge.Workflow.LifecycleTest do
  use ExUnit.Case, async: true

  alias SoundForge.Workflow.Lifecycle
  alias SoundForge.Workflow.ProcessingLifecycle

  @consult %{
    draft: [:draft, :capturing, :abandoned],
    capturing: [:capturing, :generating, :abandoned],
    generating: [:generating, :presenting, :abandoned],
    presenting: [:presenting, :promoted, :abandoned],
    promoted: [:promoted],
    abandoned: [:abandoned]
  }

  describe "can_transition?/3" do
    test "allows listed transitions" do
      assert Lifecycle.can_transition?(@consult, :draft, :capturing)
      assert Lifecycle.can_transition?(@consult, :presenting, :promoted)
    end

    test "allows explicit self-transitions" do
      assert Lifecycle.can_transition?(@consult, :draft, :draft)
    end

    test "rejects unlisted transitions" do
      refute Lifecycle.can_transition?(@consult, :draft, :promoted)
      refute Lifecycle.can_transition?(@consult, :promoted, :draft)
      refute Lifecycle.can_transition?(@consult, :abandoned, :capturing)
    end

    test "unknown from-status returns false rather than raising" do
      refute Lifecycle.can_transition?(@consult, :bogus, :draft)
    end
  end

  describe "transition/3" do
    test "returns {:ok, to} for valid transitions" do
      assert {:ok, :generating} = Lifecycle.transition(@consult, :capturing, :generating)
    end

    test "returns {:error, :invalid_transition} for invalid transitions" do
      assert {:error, :invalid_transition} = Lifecycle.transition(@consult, :promoted, :draft)
    end
  end

  describe "statuses/1 and terminal_statuses/1" do
    test "statuses collects keys and targets" do
      assert Enum.sort(Lifecycle.statuses(@consult)) ==
               Enum.sort([:draft, :capturing, :generating, :presenting, :promoted, :abandoned])
    end

    test "terminal statuses have no outgoing edges besides self" do
      assert Enum.sort(Lifecycle.terminal_statuses(@consult)) == [:abandoned, :promoted]
    end
  end

  describe "ProcessingLifecycle (use-macro concrete)" do
    test "happy path chain is fully traversable" do
      chain = [:queued, :downloading, :processing, :analyzing, :completed]

      for [from, to] <- Enum.chunk_every(chain, 2, 1, :discard) do
        assert {:ok, ^to} = ProcessingLifecycle.transition(from, to)
      end
    end

    test "failed is reachable from all active states" do
      for from <- [:queued, :downloading, :processing, :analyzing] do
        assert ProcessingLifecycle.can_transition?(from, :failed)
      end
    end

    test "completed is terminal and cannot fail" do
      refute ProcessingLifecycle.can_transition?(:completed, :failed)
      refute ProcessingLifecycle.can_transition?(:completed, :queued)
      assert :completed in ProcessingLifecycle.terminal_statuses()
    end

    test "failed can retry back to queued only" do
      assert {:ok, :queued} = ProcessingLifecycle.transition(:failed, :queued)
      assert {:error, :invalid_transition} = ProcessingLifecycle.transition(:failed, :processing)
    end

    test "skipping stages is invalid" do
      assert {:error, :invalid_transition} = ProcessingLifecycle.transition(:queued, :completed)

      assert {:error, :invalid_transition} =
               ProcessingLifecycle.transition(:downloading, :analyzing)
    end

    test "valid_status?/1 and statuses/0" do
      assert ProcessingLifecycle.valid_status?(:analyzing)
      refute ProcessingLifecycle.valid_status?(:bogus)
      assert length(ProcessingLifecycle.statuses()) == 6
    end
  end
end
