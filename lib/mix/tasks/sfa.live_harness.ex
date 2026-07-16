defmodule Mix.Tasks.Sfa.LiveHarness do
  @shortdoc "Runs the SFA live integration harness against a running server"

  @moduledoc """
  Runs the live-harness catalog against a running SFA server, prints a
  results table, writes a JSON summary under `test-results/live-harness/`,
  and exits nonzero if any step fails.

      mix sfa.live_harness
      mix sfa.live_harness --base-url http://localhost:4000
      mix sfa.live_harness --step sfa-dashboard

  Gated by `SoundForge.LiveHarness.Gate` — never runs in `:prod`.
  """

  use Mix.Task

  alias SoundForge.LiveHarness.{Catalog, Gate, Reporter, Runner, State}

  @switches [base_url: :string, step: :keep]

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = OptionParser.parse!(argv, strict: @switches)

    unless Gate.enabled?() do
      Mix.raise("Live harness is disabled in this environment (see SoundForge.LiveHarness.Gate).")
    end

    {:ok, _} = Application.ensure_all_started(:req)

    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")
    steps = resolve_steps(Keyword.get_values(opts, :step))

    Mix.shell().info("Running #{length(steps)} live-harness steps against #{base_url}\n")

    {:ok, results} = Runner.run(base_url: base_url, steps: steps)
    print_table(results)

    run_id = Reporter.run_id()

    case Reporter.report(run_id, results, base_url: base_url) do
      {:ok, %{path: path, tracker_cards: cards}} ->
        Mix.shell().info("\nSummary written to #{path} (#{cards} tracker cards posted)")

      {:error, reason} ->
        Mix.shell().error("\nFailed to write summary: #{inspect(reason)}")
    end

    coverage = State.summarize_coverage(results)

    Mix.shell().info(
      "Totals: #{coverage.pass} pass, #{coverage.warn} warn, " <>
        "#{coverage.fail} fail, #{coverage.blocked} blocked (of #{coverage.total})"
    )

    if coverage.fail > 0 or coverage.blocked > 0 do
      exit({:shutdown, 1})
    end
  end

  defp resolve_steps([]), do: Catalog.steps()

  defp resolve_steps(ids) do
    Enum.map(ids, fn id ->
      case Catalog.get(id) do
        {:ok, step} -> step
        {:error, :not_found} -> Mix.raise("Unknown step id: #{id}")
      end
    end)
  end

  defp print_table(results) do
    id_width = results |> Enum.map(&String.length(&1.id)) |> Enum.max(fn -> 4 end)

    Enum.each(results, fn result ->
      status = result.status |> to_string() |> String.upcase() |> String.pad_trailing(7)

      Mix.shell().info(
        "#{status} #{String.pad_trailing(result.id, id_width)}  " <>
          "[#{result.criterion}] #{result.message}"
      )
    end)
  end
end
