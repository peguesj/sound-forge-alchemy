defmodule SoundForge.LiveHarness.Reporter do
  @moduledoc """
  Persists live-harness run results.

  Writes a JSON summary to `test-results/live-harness/<run_id>/summary.json`
  and, when the tracker subsystem is compiled, posts each step result as a
  card to `SoundForge.Tracker.Store`. The tracker integration is guarded
  with `Code.ensure_loaded?/1` so this module never depends on the tracker
  squad's code being present.
  """

  alias SoundForge.LiveHarness.State

  @output_dir Path.join(["test-results", "live-harness"])
  @tracker_store SoundForge.Tracker.Store

  @doc "Generates a filesystem-safe run id from the current UTC time."
  @spec run_id() :: String.t()
  def run_id do
    DateTime.utc_now()
    |> DateTime.to_iso8601()
    |> String.replace(~r/[:.]/, "-")
  end

  @doc """
  Writes the run summary JSON. Options:

    * `:root` — repository root (defaults to cwd)
    * `:base_url` — recorded in the summary for provenance

  Returns `{:ok, %{path: path, summary: summary}}` or `{:error, reason}`.
  """
  @spec write_summary(String.t(), [map()], keyword()) ::
          {:ok, %{path: String.t(), summary: map()}} | {:error, term()}
  def write_summary(run_id, results, opts \\ []) do
    root = Keyword.get(opts, :root, File.cwd!())
    dir = Path.join([root, @output_dir, run_id])

    summary = %{
      run_id: run_id,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      base_url: Keyword.get(opts, :base_url),
      totals: State.summarize_coverage(results),
      results: results
    }

    with :ok <- File.mkdir_p(dir),
         {:ok, json} <- Jason.encode(summary, pretty: true),
         path = Path.join(dir, "summary.json"),
         :ok <- File.write(path, json) do
      {:ok, %{path: path, summary: summary}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Posts each result as a card to `SoundForge.Tracker.Store` if that module
  exists and exposes `add_card/2`. Returns `{:ok, posted_count}`; returns
  `{:ok, 0}` when the tracker is unavailable.

  Options:

    * `:tracker` — the tracker server (name or pid) to post to. Defaults to
      `SoundForge.Tracker.Store`. Pass an isolated instance in tests.
  """
  @spec post_to_tracker(String.t(), [map()], keyword()) :: {:ok, non_neg_integer()}
  def post_to_tracker(run_id, results, opts \\ []) do
    server = Keyword.get(opts, :tracker, @tracker_store)

    if Code.ensure_loaded?(@tracker_store) and
         function_exported?(@tracker_store, :add_card, 2) do
      posted =
        Enum.count(results, fn result ->
          card = %{
            source: "live_harness",
            run_id: run_id,
            step_id: result[:id],
            criterion: result[:criterion],
            title: result[:title],
            status: to_string(result[:status]),
            message: result[:message],
            evidence: result[:evidence],
            url: result[:url]
          }

          match?({:ok, _}, apply(@tracker_store, :add_card, [server, card]))
        end)

      {:ok, posted}
    else
      {:ok, 0}
    end
  end

  @doc "Writes the summary and posts tracker cards in one call."
  @spec report(String.t(), [map()], keyword()) ::
          {:ok, %{path: String.t(), summary: map(), tracker_cards: non_neg_integer()}}
          | {:error, term()}
  def report(run_id, results, opts \\ []) do
    with {:ok, %{path: path, summary: summary}} <- write_summary(run_id, results, opts),
         {:ok, posted} <- post_to_tracker(run_id, results, opts) do
      {:ok, %{path: path, summary: summary, tracker_cards: posted}}
    end
  end
end
