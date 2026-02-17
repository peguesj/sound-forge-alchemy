defmodule SoundForge.Debug.Jobs do
  @moduledoc """
  Debug context for querying Oban job state for the debug inspector panel.
  """

  import Ecto.Query
  alias SoundForge.Repo

  @doc "Returns the last N Oban jobs, newest first."
  def recent_jobs(limit \\ 50) do
    from(j in "oban_jobs",
      select: %{
        id: j.id,
        worker: j.worker,
        queue: j.queue,
        state: j.state,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        args: j.args,
        errors: j.errors,
        inserted_at: j.inserted_at,
        attempted_at: j.attempted_at,
        completed_at: j.completed_at,
        scheduled_at: j.scheduled_at
      },
      order_by: [desc: j.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "Returns a single Oban job by ID."
  def get_job(id) do
    from(j in "oban_jobs",
      where: j.id == ^id,
      select: %{
        id: j.id,
        worker: j.worker,
        queue: j.queue,
        state: j.state,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        args: j.args,
        errors: j.errors,
        inserted_at: j.inserted_at,
        attempted_at: j.attempted_at,
        completed_at: j.completed_at,
        scheduled_at: j.scheduled_at
      }
    )
    |> Repo.one()
  end

  @doc "Returns all Oban jobs for a given track_id, ordered by inserted_at."
  def jobs_for_track(track_id) do
    from(j in "oban_jobs",
      where: fragment("?->>'track_id' = ?", j.args, ^track_id),
      select: %{
        id: j.id,
        worker: j.worker,
        queue: j.queue,
        state: j.state,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        args: j.args,
        errors: j.errors,
        inserted_at: j.inserted_at,
        attempted_at: j.attempted_at,
        completed_at: j.completed_at,
        scheduled_at: j.scheduled_at
      },
      order_by: [asc: j.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Builds a timeline of events for a set of jobs (for a single track pipeline)."
  def build_timeline(jobs) do
    Enum.flat_map(jobs, fn job ->
      worker_short = job.worker |> String.split(".") |> List.last()
      stage = worker_to_stage(job.worker)
      error_snippet = extract_last_error(job.errors)

      events = [
        %{
          stage: stage,
          worker: worker_short,
          event: "queued",
          timestamp: job.inserted_at,
          state: job.state,
          error: nil
        }
      ]

      events =
        if job.attempted_at do
          events ++
            [
              %{
                stage: stage,
                worker: worker_short,
                event: "started",
                timestamp: job.attempted_at,
                state: job.state,
                error: nil
              }
            ]
        else
          events
        end

      events =
        if job.completed_at do
          final_event = if(job.state == "completed", do: "completed", else: "failed")

          events ++
            [
              %{
                stage: stage,
                worker: worker_short,
                event: final_event,
                timestamp: job.completed_at,
                state: job.state,
                error: if(final_event == "failed", do: error_snippet)
              }
            ]
        else
          events
        end

      events
    end)
    |> Enum.sort_by(& &1.timestamp, DateTime)
  end

  @doc "Builds the dependency graph data for D3 visualization."
  def build_graph(jobs) do
    worker_nodes =
      Enum.map(jobs, fn job ->
        worker_short = job.worker |> String.split(".") |> List.last()

        %{
          id: worker_short,
          label: worker_short,
          status: job.state,
          error: extract_last_error(job.errors)
        }
      end)
      |> Enum.uniq_by(& &1.id)

    # Add a "Stems" output node: green if analysis completed, gray otherwise
    analysis_job = Enum.find(jobs, fn j -> String.ends_with?(j.worker, "AnalysisWorker") end)

    stems_status =
      case analysis_job do
        %{state: "completed"} -> "completed"
        _ -> "pending"
      end

    nodes = worker_nodes ++ [%{id: "Stems", label: "Stems", status: stems_status, error: nil}]

    all_links = [
      %{source: "DownloadWorker", target: "ProcessingWorker"},
      %{source: "ProcessingWorker", target: "AnalysisWorker"},
      %{source: "AnalysisWorker", target: "Stems"}
    ]

    # Only include links where both source and target exist in nodes
    node_ids = MapSet.new(nodes, & &1.id)

    links =
      Enum.filter(all_links, fn link ->
        MapSet.member?(node_ids, link.source) and MapSet.member?(node_ids, link.target)
      end)

    %{nodes: nodes, links: links}
  end

  defp worker_to_stage("SoundForge.Jobs.DownloadWorker"), do: :download
  defp worker_to_stage("SoundForge.Jobs.ProcessingWorker"), do: :processing
  defp worker_to_stage("SoundForge.Jobs.AnalysisWorker"), do: :analysis
  defp worker_to_stage(_), do: :unknown

  defp extract_last_error(errors) when is_list(errors) and length(errors) > 0 do
    case List.last(errors) do
      %{"error" => msg} -> msg
      msg when is_binary(msg) -> msg
      _ -> nil
    end
  end

  defp extract_last_error(_), do: nil
end
