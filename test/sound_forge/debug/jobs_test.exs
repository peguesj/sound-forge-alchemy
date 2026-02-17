defmodule SoundForge.Debug.JobsTest do
  use SoundForge.DataCase, async: true

  alias SoundForge.Debug.Jobs

  defp insert_oban_job(attrs) do
    now = DateTime.utc_now()

    defaults = %{
      worker: "SoundForge.Jobs.DownloadWorker",
      queue: "download",
      state: "completed",
      attempt: 1,
      max_attempts: 3,
      args: %{"track_id" => Ecto.UUID.generate()},
      errors: [],
      inserted_at: now,
      attempted_at: now,
      completed_at: DateTime.add(now, 5, :second),
      scheduled_at: now
    }

    merged = Map.merge(defaults, attrs)

    {1, [job]} =
      Repo.insert_all(
        "oban_jobs",
        [
          %{
            worker: merged.worker,
            queue: merged.queue,
            state: merged.state,
            attempt: merged.attempt,
            max_attempts: merged.max_attempts,
            args: merged.args,
            errors: merged.errors,
            inserted_at: merged.inserted_at,
            attempted_at: merged.attempted_at,
            completed_at: merged.completed_at,
            scheduled_at: merged.scheduled_at
          }
        ],
        returning: [:id, :worker, :queue, :state, :attempt, :max_attempts, :args, :errors,
                    :inserted_at, :attempted_at, :completed_at, :scheduled_at]
      )

    job
  end

  describe "active_jobs/0" do
    test "returns jobs with active states" do
      active = insert_oban_job(%{state: "executing", completed_at: nil})
      queued = insert_oban_job(%{state: "available", attempted_at: nil, completed_at: nil})
      _completed = insert_oban_job(%{state: "completed"})

      jobs = Jobs.active_jobs()
      job_ids = Enum.map(jobs, & &1.id)

      assert active.id in job_ids
      assert queued.id in job_ids
      refute Enum.any?(jobs, &(&1.state == "completed"))
    end

    test "returns newest first" do
      j1 = insert_oban_job(%{state: "executing", completed_at: nil})
      j2 = insert_oban_job(%{state: "available", attempted_at: nil, completed_at: nil})

      jobs = Jobs.active_jobs()
      job_ids = Enum.map(jobs, & &1.id)

      assert Enum.find_index(job_ids, &(&1 == j2.id)) < Enum.find_index(job_ids, &(&1 == j1.id))
    end

    test "returns empty list when no active jobs" do
      insert_oban_job(%{state: "completed"})
      assert Jobs.active_jobs() == []
    end
  end

  describe "history_jobs/1" do
    test "returns completed/cancelled/discarded jobs from last 24 hours" do
      completed = insert_oban_job(%{state: "completed"})
      cancelled = insert_oban_job(%{state: "cancelled"})
      _executing = insert_oban_job(%{state: "executing", completed_at: nil})

      {jobs, _has_more} = Jobs.history_jobs()
      job_ids = Enum.map(jobs, & &1.id)

      assert completed.id in job_ids
      assert cancelled.id in job_ids
      refute Enum.any?(jobs, &(&1.state == "executing"))
    end

    test "paginates with cursor" do
      jobs = for _ <- 1..5, do: insert_oban_job(%{state: "completed"})
      sorted_ids = jobs |> Enum.sort_by(& &1.id, :desc) |> Enum.map(& &1.id)

      {first_page, has_more} = Jobs.history_jobs(limit: 3)
      assert length(first_page) == 3
      assert has_more

      cursor = List.last(first_page).id

      {second_page, has_more2} = Jobs.history_jobs(limit: 3, cursor: cursor)
      assert length(second_page) == 2
      refute has_more2

      all_ids = Enum.map(first_page ++ second_page, & &1.id)
      assert all_ids == sorted_ids
    end

    test "supports before_id as alias for cursor" do
      for _ <- 1..5, do: insert_oban_job(%{state: "completed"})

      {first_page, _} = Jobs.history_jobs(limit: 3)
      cursor = List.last(first_page).id

      {page_cursor, _} = Jobs.history_jobs(limit: 3, cursor: cursor)
      {page_before, _} = Jobs.history_jobs(limit: 3, before_id: cursor)

      assert Enum.map(page_cursor, & &1.id) == Enum.map(page_before, & &1.id)
    end

    test "returns empty when no history jobs" do
      insert_oban_job(%{state: "executing", completed_at: nil})
      {jobs, has_more} = Jobs.history_jobs()
      assert jobs == []
      refute has_more
    end
  end

  describe "recent_jobs/1" do
    test "returns recent jobs ordered newest first" do
      job1 = insert_oban_job(%{worker: "SoundForge.Jobs.DownloadWorker"})
      job2 = insert_oban_job(%{worker: "SoundForge.Jobs.ProcessingWorker"})

      jobs = Jobs.recent_jobs(50)
      job_ids = Enum.map(jobs, & &1.id)

      assert job2.id in job_ids
      assert job1.id in job_ids
      # Newest first
      assert Enum.find_index(job_ids, &(&1 == job2.id)) < Enum.find_index(job_ids, &(&1 == job1.id))
    end

    test "respects the limit" do
      for _ <- 1..5, do: insert_oban_job(%{})

      jobs = Jobs.recent_jobs(3)
      assert length(jobs) <= 3
    end
  end

  describe "get_job/1" do
    test "returns a job by ID" do
      job = insert_oban_job(%{worker: "SoundForge.Jobs.DownloadWorker"})
      result = Jobs.get_job(job.id)

      assert result.id == job.id
      assert result.worker == "SoundForge.Jobs.DownloadWorker"
      assert result.queue == "download"
    end

    test "returns nil for non-existent job" do
      assert is_nil(Jobs.get_job(-1))
    end
  end

  describe "jobs_for_track/1" do
    test "returns all jobs for a given track_id ordered by inserted_at" do
      track_id = Ecto.UUID.generate()
      other_track_id = Ecto.UUID.generate()

      _j1 = insert_oban_job(%{
        worker: "SoundForge.Jobs.DownloadWorker",
        args: %{"track_id" => track_id}
      })

      _j2 = insert_oban_job(%{
        worker: "SoundForge.Jobs.ProcessingWorker",
        args: %{"track_id" => track_id}
      })

      _other = insert_oban_job(%{
        worker: "SoundForge.Jobs.DownloadWorker",
        args: %{"track_id" => other_track_id}
      })

      jobs = Jobs.jobs_for_track(track_id)
      assert length(jobs) == 2
      assert Enum.all?(jobs, fn j -> j.args["track_id"] == track_id end)
    end
  end

  describe "build_timeline/1" do
    test "builds timeline events from jobs" do
      now = DateTime.utc_now()

      jobs = [
        %{
          worker: "SoundForge.Jobs.DownloadWorker",
          state: "completed",
          inserted_at: now,
          attempted_at: DateTime.add(now, 1, :second),
          completed_at: DateTime.add(now, 10, :second)
        }
      ]

      timeline = Jobs.build_timeline(jobs)

      assert length(timeline) == 3
      events = Enum.map(timeline, & &1.event)
      assert "queued" in events
      assert "started" in events
      assert "completed" in events
    end

    test "marks failed jobs correctly" do
      now = DateTime.utc_now()

      jobs = [
        %{
          worker: "SoundForge.Jobs.DownloadWorker",
          state: "discarded",
          inserted_at: now,
          attempted_at: DateTime.add(now, 1, :second),
          completed_at: DateTime.add(now, 5, :second)
        }
      ]

      timeline = Jobs.build_timeline(jobs)
      failed_event = Enum.find(timeline, &(&1.event == "failed"))
      assert failed_event
    end

    test "omits started event when attempted_at is nil" do
      now = DateTime.utc_now()

      jobs = [
        %{
          worker: "SoundForge.Jobs.DownloadWorker",
          state: "available",
          inserted_at: now,
          attempted_at: nil,
          completed_at: nil
        }
      ]

      timeline = Jobs.build_timeline(jobs)
      assert length(timeline) == 1
      assert hd(timeline).event == "queued"
    end

    test "sorts events by timestamp" do
      t1 = ~U[2026-02-17 10:00:00Z]
      t2 = ~U[2026-02-17 10:00:05Z]
      t3 = ~U[2026-02-17 10:00:10Z]

      jobs = [
        %{
          worker: "SoundForge.Jobs.ProcessingWorker",
          state: "completed",
          inserted_at: t2,
          attempted_at: t2,
          completed_at: t3
        },
        %{
          worker: "SoundForge.Jobs.DownloadWorker",
          state: "completed",
          inserted_at: t1,
          attempted_at: t1,
          completed_at: t2
        }
      ]

      timeline = Jobs.build_timeline(jobs)
      timestamps = Enum.map(timeline, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps, DateTime)
    end
  end

  describe "build_graph/1" do
    test "builds graph nodes from jobs with correct fields" do
      jobs = [
        %{
          worker: "SoundForge.Jobs.DownloadWorker",
          state: "completed",
          errors: []
        },
        %{
          worker: "SoundForge.Jobs.ProcessingWorker",
          state: "executing",
          errors: []
        }
      ]

      %{nodes: nodes, links: links} = Jobs.build_graph(jobs)

      # 2 worker nodes + 1 Stems output node
      assert length(nodes) == 3
      download_node = Enum.find(nodes, &(&1.id == "DownloadWorker"))
      assert download_node.status == "completed"

      processing_node = Enum.find(nodes, &(&1.id == "ProcessingWorker"))
      assert processing_node.status == "executing"

      stems_node = Enum.find(nodes, &(&1.id == "Stems"))
      assert stems_node.status == "pending"

      assert length(links) == 1
      assert hd(links).source == "DownloadWorker"
      assert hd(links).target == "ProcessingWorker"
    end

    test "includes error message in graph nodes" do
      jobs = [
        %{
          worker: "SoundForge.Jobs.DownloadWorker",
          state: "discarded",
          errors: [%{"error" => "Download failed: timeout"}]
        }
      ]

      %{nodes: nodes} = Jobs.build_graph(jobs)
      node = hd(nodes)
      assert node.error == "Download failed: timeout"
    end

    test "deduplicates nodes by worker" do
      jobs = [
        %{worker: "SoundForge.Jobs.DownloadWorker", state: "completed", errors: []},
        %{worker: "SoundForge.Jobs.DownloadWorker", state: "discarded", errors: []}
      ]

      %{nodes: nodes} = Jobs.build_graph(jobs)
      # 1 deduplicated worker node + 1 Stems output node
      assert length(nodes) == 2
      worker_nodes = Enum.reject(nodes, &(&1.id == "Stems"))
      assert length(worker_nodes) == 1
    end

    test "only includes links where both nodes exist" do
      jobs = [
        %{worker: "SoundForge.Jobs.AnalysisWorker", state: "completed", errors: []}
      ]

      %{links: links} = Jobs.build_graph(jobs)
      # Only Analysis -> Stems link exists (no Download or Processing nodes)
      assert length(links) == 1
      assert hd(links).source == "AnalysisWorker"
      assert hd(links).target == "Stems"
    end

    test "includes full pipeline links for all three workers" do
      jobs = [
        %{worker: "SoundForge.Jobs.DownloadWorker", state: "completed", errors: []},
        %{worker: "SoundForge.Jobs.ProcessingWorker", state: "completed", errors: []},
        %{worker: "SoundForge.Jobs.AnalysisWorker", state: "completed", errors: []}
      ]

      %{links: links} = Jobs.build_graph(jobs)
      # Download -> Processing, Processing -> Analysis, Analysis -> Stems
      assert length(links) == 3
    end
  end

  describe "worker_stats/0" do
    test "returns stats for all three worker types" do
      stats = Jobs.worker_stats()
      assert length(stats) == 3
      workers = Enum.map(stats, & &1.worker)
      assert "DownloadWorker" in workers
      assert "ProcessingWorker" in workers
      assert "AnalysisWorker" in workers
    end

    test "returns zeroed counts when no jobs exist" do
      stats = Jobs.worker_stats()

      Enum.each(stats, fn ws ->
        assert ws.running == 0
        assert ws.queued == 0
        assert ws.failed == 0
        assert ws.status == :idle
      end)
    end

    test "counts executing jobs as running" do
      insert_oban_job(%{
        worker: "SoundForge.Jobs.DownloadWorker",
        state: "executing",
        completed_at: nil
      })

      stats = Jobs.worker_stats()
      download = Enum.find(stats, &(&1.worker == "DownloadWorker"))
      assert download.running == 1
      assert download.status == :active
    end

    test "counts available and scheduled jobs as queued" do
      insert_oban_job(%{
        worker: "SoundForge.Jobs.ProcessingWorker",
        state: "available",
        attempted_at: nil,
        completed_at: nil
      })

      insert_oban_job(%{
        worker: "SoundForge.Jobs.ProcessingWorker",
        state: "scheduled",
        attempted_at: nil,
        completed_at: nil
      })

      stats = Jobs.worker_stats()
      processing = Enum.find(stats, &(&1.worker == "ProcessingWorker"))
      assert processing.queued == 2
    end

    test "counts discarded jobs from last hour as failed" do
      insert_oban_job(%{
        worker: "SoundForge.Jobs.AnalysisWorker",
        state: "discarded",
        attempted_at: DateTime.utc_now()
      })

      stats = Jobs.worker_stats()
      analysis = Enum.find(stats, &(&1.worker == "AnalysisWorker"))
      assert analysis.failed == 1
      assert analysis.status == :errored
    end

    test "errored status takes priority over active" do
      insert_oban_job(%{
        worker: "SoundForge.Jobs.DownloadWorker",
        state: "executing",
        completed_at: nil
      })

      insert_oban_job(%{
        worker: "SoundForge.Jobs.DownloadWorker",
        state: "discarded",
        attempted_at: DateTime.utc_now()
      })

      stats = Jobs.worker_stats()
      download = Enum.find(stats, &(&1.worker == "DownloadWorker"))
      assert download.status == :errored
    end
  end
end
