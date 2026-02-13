# ADR-003: Oban over GenStage, Broadway, and Redis for Job Processing

**Status**: Accepted
**Date**: 2025-12-16
**Deciders**: Project Lead
**Context**: Sound Forge Alchemy requires reliable background job processing for downloads, analysis, and stem separation

## Context

The Node.js version of Sound Forge Alchemy used Redis (via Bull/BullMQ) as a job queue for:

- **Downloads**: Fetching audio files from Spotify URLs via spotdl
- **Analysis**: Running librosa-based audio feature extraction
- **Processing**: Running demucs-based stem separation

Each job type had different concurrency requirements, retry behavior, and progress reporting needs. The Redis-based system required a running Redis instance, custom retry logic, and Socket.IO for real-time progress updates.

For the Elixir port, a job processing system is needed that provides persistence, retries, concurrency control, and observability without adding infrastructure dependencies beyond PostgreSQL (which is already required for Ecto).

## Decision

Use **Oban** (`{:oban, "~> 2.18"}`) with PostgreSQL-backed queues for all background job processing. Configure three queues with appropriate concurrency limits:

```elixir
config :sound_forge, Oban,
  repo: SoundForge.Repo,
  queues: [download: 3, processing: 2, analysis: 2]
```

## Rationale

### 1. PostgreSQL-Backed Persistence (Replaces Redis)

Oban stores jobs in the PostgreSQL database using Ecto. This eliminates Redis as an infrastructure dependency. Jobs survive application restarts, database backups include job history, and the existing Ecto/Repo infrastructure handles all data access.

The Node.js version required both PostgreSQL (for application data) and Redis (for job queues). The Elixir version requires only PostgreSQL.

### 2. Built-in Retry with Configurable Backoff

Oban provides automatic retries with exponential backoff. Each worker specifies `max_attempts`:

```elixir
use Oban.Worker, queue: :download, max_attempts: 3
```

Failed jobs are retried automatically. After exhausting retries, jobs move to a `discarded` state that can be inspected. The Node.js version required custom retry logic in Bull that was fragile and inconsistently applied across job types.

### 3. Queue-Level Concurrency Control

Oban enforces concurrency limits per queue. `download: 3` means at most 3 downloads run simultaneously. This prevents overwhelming spotdl, the filesystem, or the network. `processing: 2` and `analysis: 2` limit CPU-intensive Python Port processes.

These limits are configured centrally in `config/config.exs` and enforced by Oban's queue manager. The Node.js version had concurrency configured per-worker with inconsistent enforcement.

### 4. Job Uniqueness

Oban's uniqueness constraints prevent duplicate job insertion. A user double-clicking "Download" will not create two download jobs for the same track:

```elixir
use Oban.Worker,
  queue: :download,
  unique: [period: 300, fields: [:args], keys: [:track_id]]
```

The Node.js version handled this with application-level checks that had race conditions.

### 5. Observability via Oban Web

Oban Web (optional paid add-on) provides a web dashboard for inspecting queues, job states, failure reasons, and retry history. Even without Oban Web, jobs are queryable via Ecto:

```elixir
Oban.Job
|> where([j], j.queue == "download" and j.state == "retryable")
|> Repo.all()
```

The Node.js version required Bull Board (a separate npm package) and a separate Express route for the dashboard.

### 6. Telemetry Integration

Oban emits telemetry events for job execution, completion, failure, and queue metrics. These integrate with Phoenix.LiveDashboard for real-time monitoring:

```elixir
# Already available in SoundForgeWeb.Telemetry
:telemetry.attach("oban-job-start", [:oban, :job, :start], &handle_event/4, nil)
:telemetry.attach("oban-job-stop", [:oban, :job, :stop], &handle_event/4, nil)
:telemetry.attach("oban-job-exception", [:oban, :job, :exception], &handle_event/4, nil)
```

### 7. Compatibility with PubSub Progress Reporting

Oban workers run in regular Elixir processes with access to all OTP facilities. Broadcasting progress via `Phoenix.PubSub` from inside an Oban worker is straightforward:

```elixir
def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
  broadcast_progress(job_id, :downloading, 25)
  # ... do work ...
  broadcast_progress(job_id, :completed, 100)
end
```

This replaces Socket.IO from the Node.js version with Phoenix PubSub + LiveView, keeping progress reporting entirely within the Elixir ecosystem.

## Alternatives Considered

### Alternative 1: GenStage

**What it offers**: A behaviour for building data processing pipelines with back-pressure. Producers emit events, consumers process them, with demand-driven flow control.

**Why rejected**:

- **No persistence**: GenStage is in-memory. If the application restarts, all pending and in-progress jobs are lost. Audio downloads and analysis results must survive restarts.
- **No retry**: GenStage has no built-in retry mechanism. Failed events are discarded unless custom retry logic is implemented -- exactly the fragile approach the Node.js version had.
- **Pipeline oriented**: GenStage is designed for continuous data flow (stream processing), not discrete job execution. Sound Forge jobs are discrete: "download this track", "analyze this file". They do not form a continuous stream.
- **No observability**: No dashboard, no job history, no failure inspection without building it from scratch.
- **Complexity**: Setting up a GenStage pipeline with producers, producer-consumers, and consumers for three job types is significantly more code than three Oban workers.

### Alternative 2: Broadway

**What it offers**: Built on GenStage, Broadway provides a high-level abstraction for data ingestion pipelines with built-in batching, rate limiting, and integration with message brokers (SQS, RabbitMQ, Kafka).

**Why rejected**:

- **Data ingestion focus**: Broadway is optimized for consuming messages from external sources (queues, streams) and processing them in batches. Sound Forge jobs are user-initiated, not stream-consumed.
- **External broker dependency**: Broadway's strength is integrating with SQS, RabbitMQ, or Kafka. Using Broadway without an external broker means implementing a custom producer -- at which point Oban is simpler.
- **No job-level features**: Broadway does not provide job uniqueness, per-job retry with backoff, or job state inspection. These are critical for Sound Forge's user-facing progress reporting.
- **Batch processing mismatch**: Broadway batches events for efficiency. Sound Forge processes one audio file at a time with individual progress reporting. Batching adds complexity without benefit.

### Alternative 3: Keep Redis (via Redix + Custom Workers)

**What it offers**: Direct port of the Node.js Bull/BullMQ architecture using Redix (Elixir Redis client) with custom worker processes.

**Why rejected**:

- **Infrastructure dependency**: Redis is an additional service to deploy, monitor, back up, and maintain. PostgreSQL is already required. Oban eliminates the Redis dependency entirely.
- **Custom code**: Bull's features (delayed jobs, priority, repeatable, rate limiting) would need to be reimplemented in Elixir. Oban provides all of these out of the box.
- **Data split**: With Redis for jobs and PostgreSQL for application data, querying the relationship between jobs and tracks requires cross-system joins. With Oban, everything is in PostgreSQL and queryable via Ecto.
- **Operational complexity**: Redis has its own persistence model (RDB/AOF), memory management, and failure modes. One fewer service means one fewer thing that can go wrong in production.
- **No Ecto integration**: Custom Redis-backed workers would not benefit from Ecto's transaction support, changeset validation, or telemetry integration.

## Consequences

### Positive

- Single infrastructure dependency (PostgreSQL) instead of PostgreSQL + Redis
- Jobs survive application restarts (persistent in database)
- Automatic retries with exponential backoff
- Queue-level concurrency control configured centrally
- Job uniqueness prevents duplicate processing
- Full job history queryable via Ecto
- Telemetry integration with Phoenix.LiveDashboard
- PubSub broadcasting works naturally from Oban workers
- Optional Oban Web dashboard for production observability

### Negative

- PostgreSQL handles both application data and job queue load (monitor for contention)
- Oban's polling interval (default 1 second) adds slight latency compared to Redis pub/sub notification
- Oban Pro/Web features (rate limiting, batch jobs, workflow orchestration) require a paid license
- Job table can grow large if not pruned (Oban provides `Oban.Plugins.Pruner` for this)

### Neutral

- Migration to a separate job service is possible by replacing Oban workers with HTTP calls to an external service
- Oban's PostgreSQL-backed approach is used by many production Elixir applications (well-tested pattern)
- The three-queue configuration (`download: 3, processing: 2, analysis: 2`) can be tuned per environment via config

## Queue Configuration Rationale

| Queue | Concurrency | Reasoning |
|-------|-------------|-----------|
| `download` | 3 | Downloads are I/O-bound (network). 3 concurrent downloads saturate a typical connection without overwhelming spotdl. |
| `processing` | 2 | Stem separation via demucs is CPU-intensive (PyTorch inference). 2 concurrent processes prevent CPU starvation for the BEAM and other workers. |
| `analysis` | 2 | Feature extraction via librosa is CPU-intensive (FFT, spectral analysis). Same rationale as processing. |

Total maximum concurrent Python processes: 4 (2 processing + 2 analysis). This is appropriate for a single-server deployment with 4-8 CPU cores.
