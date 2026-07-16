defmodule SoundForge.LiveHarness.State do
  @moduledoc """
  Pure state derivation for the live harness — port of vyynl-sales-web's
  `live-state.ts`.

  Derives an overall workflow status and the four workflow phases
  (`scan -> correlate -> github -> fix`) from the latest run summary.
  """

  @phases [
    {"scan", "Scan latest run summary"},
    {"correlate", "Correlate failures with catalog"},
    {"github", "Publish evidence"},
    {"fix", "Fix and re-run"}
  ]

  @type status :: :idle | :awaiting_fresh_run | :awaiting_fix | :complete
  @type phase_status :: :pending | :running | :pass | :warn | :fail | :blocked

  @type phase :: %{id: String.t(), label: String.t(), status: phase_status(), message: String.t()}

  @type t :: %{status: status(), phases: [phase()], coverage: map()}

  @doc """
  Derives harness state from a summary.

  `summary` is `nil` (no run yet) or a map with a `:results` list of
  per-step result maps (`%{status: :pass | :warn | :fail | :blocked, ...}`).
  Options:

    * `:fresh` — whether the summary reflects the current code (default true).
      A stale summary yields `:awaiting_fresh_run`.
  """
  @spec derive(map() | nil, keyword()) :: t()
  def derive(summary, opts \\ [])

  def derive(nil, _opts) do
    %{
      status: :idle,
      phases: build_phases(%{}, "No run summary found yet."),
      coverage: summarize_coverage([])
    }
  end

  def derive(%{} = summary, opts) do
    fresh? = Keyword.get(opts, :fresh, true)
    results = Map.get(summary, :results) || Map.get(summary, "results") || []
    coverage = summarize_coverage(results)

    cond do
      not fresh? ->
        %{
          status: :awaiting_fresh_run,
          phases:
            build_phases(
              %{"scan" => {:warn, "Run summary is stale; re-run the harness."}},
              "Awaiting a fresh run."
            ),
          coverage: coverage
        }

      coverage.fail > 0 or coverage.blocked > 0 ->
        %{
          status: :awaiting_fix,
          phases:
            build_phases(
              %{
                "scan" => {:pass, "Run #{run_id(summary)} scanned."},
                "correlate" =>
                  {:pass,
                   "#{coverage.fail} failing / #{coverage.blocked} blocked steps correlated."},
                "github" => {:pass, "Evidence recorded."},
                "fix" => {:running, "Fix failing steps, then re-run the harness."}
              },
              ""
            ),
          coverage: coverage
        }

      true ->
        %{
          status: :complete,
          phases:
            build_phases(
              %{
                "scan" => {:pass, "Run #{run_id(summary)} scanned."},
                "correlate" => {:pass, "No failing steps."},
                "github" => {:pass, "Evidence recorded."},
                "fix" => {:pass, "Nothing to fix."}
              },
              ""
            ),
          coverage: coverage
        }
    end
  end

  @doc """
  Summarizes coverage totals from a result list.
  """
  @spec summarize_coverage([map()]) :: %{
          total: non_neg_integer(),
          pass: non_neg_integer(),
          warn: non_neg_integer(),
          fail: non_neg_integer(),
          blocked: non_neg_integer(),
          pass_rate: float()
        }
  def summarize_coverage(results) when is_list(results) do
    counts =
      Enum.reduce(results, %{pass: 0, warn: 0, fail: 0, blocked: 0}, fn result, acc ->
        status = normalize_status(Map.get(result, :status) || Map.get(result, "status"))
        Map.update(acc, status, 1, &(&1 + 1))
      end)

    total = length(results)

    Map.merge(counts, %{
      total: total,
      pass_rate: if(total == 0, do: 0.0, else: Float.round(counts.pass / total, 4))
    })
  end

  defp normalize_status(status) when status in [:pass, :warn, :fail, :blocked], do: status
  defp normalize_status("pass"), do: :pass
  defp normalize_status("warn"), do: :warn
  defp normalize_status("fail"), do: :fail
  defp normalize_status(_), do: :blocked

  defp run_id(summary), do: Map.get(summary, :run_id) || Map.get(summary, "run_id") || "unknown"

  defp build_phases(overrides, default_message) do
    Enum.map(@phases, fn {id, label} ->
      {status, message} = Map.get(overrides, id, {:pending, default_message})
      %{id: id, label: label, status: status, message: message}
    end)
  end
end
