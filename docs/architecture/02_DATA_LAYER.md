---
title: Data Layer
nav_order: 12
parent: Architecture
---
# Data Layer

## Overview

Sound Forge Alchemy uses Ecto 3.13 with the Postgres adapter (`Ecto.Adapters.Postgres` via Postgrex) for all data access. The repository is defined at `SoundForge.Repo` and configured as a supervised child in the application supervision tree. All schemas use binary UUID primary keys, UTC datetime timestamps, and foreign key constraints with cascading deletes.

## Ecto Schemas

### Track

```elixir
# lib/sound_forge/music/track.ex
defmodule SoundForge.Music.Track do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tracks" do
    field :spotify_id, :string
    field :spotify_url, :string
    field :title, :string
    field :artist, :string
    field :album, :string
    field :album_art_url, :string
    field :duration, :integer

    has_many :download_jobs, SoundForge.Music.DownloadJob
    has_many :processing_jobs, SoundForge.Music.ProcessingJob
    has_many :analysis_jobs, SoundForge.Music.AnalysisJob
    has_many :stems, SoundForge.Music.Stem
    has_many :analysis_results, SoundForge.Music.AnalysisResult

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(track, attrs) do
    track
    |> cast(attrs, [:spotify_id, :spotify_url, :title, :artist, :album, :album_art_url, :duration])
    |> validate_required([:title])
    |> unique_constraint(:spotify_id)
  end
end
```

### DownloadJob

```elixir
# lib/sound_forge/music/download_job.ex
defmodule SoundForge.Music.DownloadJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_values [:queued, :downloading, :processing, :completed, :failed]

  schema "download_jobs" do
    field :status, Ecto.Enum, values: @status_values, default: :queued
    field :progress, :integer, default: 0
    field :output_path, :string
    field :file_size, :integer
    field :error, :string

    belongs_to :track, SoundForge.Music.Track

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(download_job, attrs) do
    download_job
    |> cast(attrs, [:track_id, :status, :progress, :output_path, :file_size, :error])
    |> validate_required([:track_id])
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:track_id)
  end
end
```

### ProcessingJob

```elixir
# lib/sound_forge/music/processing_job.ex
defmodule SoundForge.Music.ProcessingJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_values [:queued, :downloading, :processing, :completed, :failed]

  schema "processing_jobs" do
    field :model, :string, default: "htdemucs"
    field :status, Ecto.Enum, values: @status_values, default: :queued
    field :progress, :integer, default: 0
    field :output_path, :string
    field :options, :map
    field :error, :string

    belongs_to :track, SoundForge.Music.Track
    has_many :stems, SoundForge.Music.Stem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(processing_job, attrs) do
    processing_job
    |> cast(attrs, [:track_id, :model, :status, :progress, :output_path, :options, :error])
    |> validate_required([:track_id])
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:track_id)
  end
end
```

### AnalysisJob

```elixir
# lib/sound_forge/music/analysis_job.ex
defmodule SoundForge.Music.AnalysisJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_values [:queued, :downloading, :processing, :completed, :failed]

  schema "analysis_jobs" do
    field :status, Ecto.Enum, values: @status_values, default: :queued
    field :progress, :integer, default: 0
    field :results, :map
    field :error, :string

    belongs_to :track, SoundForge.Music.Track
    has_one :analysis_result, SoundForge.Music.AnalysisResult

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(analysis_job, attrs) do
    analysis_job
    |> cast(attrs, [:track_id, :status, :progress, :results, :error])
    |> validate_required([:track_id])
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:track_id)
  end
end
```

### Stem

```elixir
# lib/sound_forge/music/stem.ex
defmodule SoundForge.Music.Stem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @stem_type_values [:vocals, :drums, :bass, :other]

  schema "stems" do
    field :stem_type, Ecto.Enum, values: @stem_type_values
    field :file_path, :string
    field :file_size, :integer

    belongs_to :processing_job, SoundForge.Music.ProcessingJob
    belongs_to :track, SoundForge.Music.Track

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(stem, attrs) do
    stem
    |> cast(attrs, [:processing_job_id, :track_id, :stem_type, :file_path, :file_size])
    |> validate_required([:processing_job_id, :track_id, :stem_type])
    |> validate_inclusion(:stem_type, @stem_type_values)
    |> foreign_key_constraint(:processing_job_id)
    |> foreign_key_constraint(:track_id)
  end
end
```

### AnalysisResult

```elixir
# lib/sound_forge/music/analysis_result.ex
defmodule SoundForge.Music.AnalysisResult do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "analysis_results" do
    field :tempo, :float
    field :key, :string
    field :energy, :float
    field :spectral_centroid, :float
    field :spectral_rolloff, :float
    field :zero_crossing_rate, :float
    field :features, :map

    belongs_to :track, SoundForge.Music.Track
    belongs_to :analysis_job, SoundForge.Music.AnalysisJob

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(analysis_result, attrs) do
    analysis_result
    |> cast(attrs, [
      :track_id,
      :analysis_job_id,
      :tempo,
      :key,
      :energy,
      :spectral_centroid,
      :spectral_rolloff,
      :zero_crossing_rate,
      :features
    ])
    |> validate_required([:track_id, :analysis_job_id])
    |> foreign_key_constraint(:track_id)
    |> foreign_key_constraint(:analysis_job_id)
  end
end
```

## Repository

```elixir
# lib/sound_forge/repo.ex
defmodule SoundForge.Repo do
  use Ecto.Repo,
    otp_app: :sound_forge,
    adapter: Ecto.Adapters.Postgres
end
```

Configuration in `config/config.exs`:

```elixir
config :sound_forge,
  ecto_repos: [SoundForge.Repo],
  generators: [timestamp_type: :utc_datetime]
```

Production database URL is loaded from the `DATABASE_URL` environment variable in `config/runtime.exs`.

## PostgreSQL Table Schemas

### Migration 1: Music Tables

**File:** `priv/repo/migrations/20260212040000_create_music_tables.exs`

This single migration creates all six application tables. Tables are created in dependency order -- `tracks` first (no FK dependencies), then job tables (FK to tracks), then output tables (FK to jobs and tracks).

```elixir
defmodule SoundForge.Repo.Migrations.CreateMusicTables do
  use Ecto.Migration

  def change do
    # ── tracks ──────────────────────────────────────────────────────
    create table(:tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :spotify_id, :text
      add :spotify_url, :text
      add :title, :text, null: false
      add :artist, :text
      add :album, :text
      add :album_art_url, :text
      add :duration, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tracks, [:spotify_id])
    create index(:tracks, [:inserted_at])

    # ── download_jobs ───────────────────────────────────────────────
    create table(:download_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "queued"
      add :progress, :integer, default: 0
      add :output_path, :text
      add :file_size, :bigint
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:download_jobs, [:track_id])
    create index(:download_jobs, [:status])
    create index(:download_jobs, [:inserted_at])

    # ── processing_jobs ─────────────────────────────────────────────
    create table(:processing_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :model, :text, default: "htdemucs"
      add :status, :string, null: false, default: "queued"
      add :progress, :integer, default: 0
      add :output_path, :text
      add :options, :map
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:processing_jobs, [:track_id])
    create index(:processing_jobs, [:status])
    create index(:processing_jobs, [:inserted_at])

    # ── analysis_jobs ───────────────────────────────────────────────
    create table(:analysis_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "queued"
      add :progress, :integer, default: 0
      add :results, :map
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:analysis_jobs, [:track_id])
    create index(:analysis_jobs, [:status])
    create index(:analysis_jobs, [:inserted_at])

    # ── stems ───────────────────────────────────────────────────────
    create table(:stems, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :processing_job_id,
          references(:processing_jobs, type: :binary_id, on_delete: :delete_all), null: false
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :stem_type, :string, null: false
      add :file_path, :text
      add :file_size, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:stems, [:processing_job_id])
    create index(:stems, [:track_id])
    create index(:stems, [:inserted_at])

    # ── analysis_results ────────────────────────────────────────────
    create table(:analysis_results, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :analysis_job_id, references(:analysis_jobs, type: :binary_id, on_delete: :delete_all),
        null: false
      add :tempo, :float
      add :key, :text
      add :energy, :float
      add :spectral_centroid, :float
      add :spectral_rolloff, :float
      add :zero_crossing_rate, :float
      add :features, :map

      timestamps(type: :utc_datetime)
    end

    create index(:analysis_results, [:track_id])
    create index(:analysis_results, [:analysis_job_id])
    create index(:analysis_results, [:inserted_at])
  end
end
```

### Migration 2: Oban Jobs Table

**File:** `priv/repo/migrations/20260212081450_add_oban_jobs_table.exs`

Oban manages its own table schema. The migration delegates to `Oban.Migration` which creates the `oban_jobs` table, `oban_producers` table, indexes, and triggers for job notification.

```elixir
defmodule SoundForge.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 1)
  end
end
```

## Index Justifications

### tracks

| Index | Type | Justification |
|-------|------|---------------|
| `unique_index(:tracks, [:spotify_id])` | Unique B-tree | Prevents duplicate track imports from the same Spotify ID. Also accelerates `Repo.get_by(Track, spotify_id: id)` lookups used in `Jobs.Download.find_or_create_track/1`. |
| `index(:tracks, [:inserted_at])` | B-tree | Supports chronological listing of tracks. `Music.list_tracks/0` currently does not order, but this index anticipates the addition of `order_by: [desc: :inserted_at]`. |

### download_jobs / processing_jobs / analysis_jobs

All three job tables share the same index pattern:

| Index | Type | Justification |
|-------|------|---------------|
| `index(:*_jobs, [:track_id])` | B-tree | Supports `WHERE track_id = ?` queries. Used when loading all jobs for a track, and for the `belongs_to` association. Also required for efficient cascading deletes when a track is deleted. |
| `index(:*_jobs, [:status])` | B-tree | Supports filtering jobs by status (e.g., "show all queued jobs", "find failed jobs for retry"). Low cardinality (5 values) but still beneficial for selective queries like `WHERE status = 'failed'`. |
| `index(:*_jobs, [:inserted_at])` | B-tree | Supports chronological ordering of jobs. Useful for dashboard views showing recent activity and for cleanup queries targeting old completed jobs. |

### stems

| Index | Type | Justification |
|-------|------|---------------|
| `index(:stems, [:processing_job_id])` | B-tree | Supports loading all stems produced by a specific processing job. Used by the `has_many :stems` association on `ProcessingJob`. |
| `index(:stems, [:track_id])` | B-tree | Supports `Music.list_stems_for_track/1` which queries `WHERE track_id = ?`. This is the primary query pattern for displaying stems on the dashboard. |
| `index(:stems, [:inserted_at])` | B-tree | Supports chronological ordering. |

### analysis_results

| Index | Type | Justification |
|-------|------|---------------|
| `index(:analysis_results, [:track_id])` | B-tree | Supports `Music.get_analysis_result_for_track/1` which queries `WHERE track_id = ?`. This is the primary query pattern for displaying analysis data on the dashboard. |
| `index(:analysis_results, [:analysis_job_id])` | B-tree | Supports the `has_one :analysis_result` association on `AnalysisJob`. Also required for efficient cascading deletes. |
| `index(:analysis_results, [:inserted_at])` | B-tree | Supports chronological ordering. |

### Indexes Not Yet Created (Future Considerations)

| Table | Potential Index | Rationale |
|-------|----------------|-----------|
| `tracks` | `index(:tracks, [:title], using: :gin, opclass: "gin_trgm_ops")` | Would accelerate the `ILIKE` search in `Music.search_tracks/1`. Requires the `pg_trgm` extension. Currently the table is small enough that sequential scan is acceptable. |
| `stems` | `index(:stems, [:stem_type])` | Would support queries like "get all vocal stems". Low cardinality (4 values) makes this marginal. |
| `analysis_results` | `index(:analysis_results, [:tempo])` | Would support range queries like "find tracks between 120-130 BPM". Only valuable once the track count grows. |

## Binary UUID Primary Keys

All tables use `binary_id` (UUID v4) primary keys instead of auto-incrementing integers:

```elixir
@primary_key {:id, :binary_id, autogenerate: true}
@foreign_key_type :binary_id
```

In the migration:

```elixir
create table(:tracks, primary_key: false) do
  add :id, :binary_id, primary_key: true
  ...
end
```

### Rationale

**Globally unique without coordination.** UUIDs are generated client-side by Ecto without querying a database sequence. This matters for:
- Job creation in Oban workers where the job ID may be known before the database insert
- Potential future sharding or multi-node deployment where sequence coordination is expensive
- API responses that include IDs before the transaction commits

**No information leakage.** Sequential integer IDs reveal record count and creation order. UUID v4 is random, preventing enumeration attacks on the API (e.g., incrementing `/api/download/job/1`, `/api/download/job/2`).

**Consistent with Oban.** Oban's internal job IDs are integers, but all application-level references (track IDs, job IDs in the domain model) use UUIDs. This prevents confusion between Oban's internal job ID and the application's `DownloadJob.id`.

**Storage trade-off.** `binary_id` stores as 16 bytes in PostgreSQL (same as `uuid` type), compared to 4 bytes for an integer. For this application's scale (thousands of tracks, not millions), the difference is negligible. The `binary_id` type is stored in its raw binary form, not as a 36-character string, so the overhead is minimal.

### Database Column Types

The migration uses `binary_id` which Ecto maps to PostgreSQL's `uuid` type. This is a 128-bit type stored as 16 bytes. PostgreSQL natively supports UUID comparison, indexing, and generation.

## Cascading Deletes

All foreign key constraints use `on_delete: :delete_all`:

```elixir
add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
```

This means deleting a `Track` record automatically deletes:
- All `DownloadJob` records for that track
- All `ProcessingJob` records for that track
- All `AnalysisJob` records for that track
- All `Stem` records for that track (both via `track_id` FK and via `processing_job_id` cascade)
- All `AnalysisResult` records for that track (both via `track_id` FK and via `analysis_job_id` cascade)

The cascade is database-level, not application-level, so it executes in a single transaction regardless of Ecto preloading. This is important because deleting a track with many associated records should be atomic.

**Note:** File cleanup is not handled by cascading deletes. The `SoundForge.Storage` module's `cleanup_orphaned/0` function (currently a placeholder) will need to be called after track deletion to remove orphaned files from the filesystem.

## Ecto.Enum for Status Fields

Status fields on all three job types use `Ecto.Enum`:

```elixir
@status_values [:queued, :downloading, :processing, :completed, :failed]

field :status, Ecto.Enum, values: @status_values, default: :queued
```

In PostgreSQL, these are stored as `:string` (varchar) columns. `Ecto.Enum` handles the atom-to-string conversion transparently:
- Writing: `%{status: :downloading}` is stored as `"downloading"` in the database
- Reading: `"downloading"` from the database is loaded as `:downloading` in Elixir
- Validation: `validate_inclusion(:status, @status_values)` ensures only valid values are persisted

The migration defines the column as `:string` with a default of `"queued"`:

```elixir
add :status, :string, null: false, default: "queued"
```

### Why Not PostgreSQL Enums?

Using varchar instead of a PostgreSQL `CREATE TYPE ... AS ENUM` was a deliberate choice:
- Adding new status values does not require an `ALTER TYPE` migration
- Ecto.Enum provides the same validation at the application level
- PostgreSQL enum types cannot have values removed, only added
- Simpler migration rollback (no type dependency issues)

## Map/JSON Columns

Three columns use the `:map` type, which maps to PostgreSQL's `jsonb`:

| Table | Column | Content |
|-------|--------|---------|
| `processing_jobs` | `options` | Processing configuration: `%{file_path: "...", model: "htdemucs"}` |
| `analysis_jobs` | `results` | Inline results: `%{type: "full", file_path: "..."}` |
| `analysis_results` | `features` | Extended feature data: MFCC arrays, chroma vectors, etc. |

`jsonb` was chosen over `json` because:
- `jsonb` supports GIN indexing for future `@>` containment queries
- `jsonb` deduplicates keys and normalizes whitespace, saving storage
- `jsonb` supports partial updates via `jsonb_set()` (useful for incrementally adding features)

## File Size Columns

The `file_size` columns on `download_jobs` and `stems` use `:bigint` (8 bytes) rather than `:integer` (4 bytes):

```elixir
add :file_size, :bigint
```

This supports files up to 9.2 exabytes. While this is extreme for audio files, it prevents the 2GB integer overflow that would occur with a 4-byte integer for any file larger than ~2.1 GB. Uncompressed audio stems from long tracks can approach or exceed 2 GB.

## Optimistic Locking (Planned)

Optimistic locking via a `version` field is planned but not yet implemented. The design:

```elixir
# Future addition to all job schemas
field :lock_version, :integer, default: 1
```

```elixir
# Future addition to changesets
|> optimistic_lock(:lock_version)
```

This would prevent race conditions where two Oban workers attempt to update the same job record simultaneously (e.g., a retry running concurrently with a progress update). Ecto's `optimistic_lock/2` adds a `WHERE lock_version = ?` clause to UPDATE statements and raises `Ecto.StaleEntryError` on conflict.

The current implementation avoids this issue in practice because:
- Each job has a single worker, and Oban's unique job constraints prevent duplicate execution
- Progress updates are append-only (never decrease), so a stale write still moves forward
- Status transitions are forward-only (see `01_DOMAIN_MODEL.md`), so a stale write cannot regress state

Optimistic locking will become necessary when:
- Multiple processes can update the same job (e.g., cancellation from the UI while a worker is running)
- Batch operations update multiple jobs in parallel
- The system moves to a multi-node deployment

## Timestamp Strategy

All schemas use UTC datetime timestamps:

```elixir
timestamps(type: :utc_datetime)
```

Configured globally in `config/config.exs`:

```elixir
config :sound_forge,
  generators: [timestamp_type: :utc_datetime]
```

This stores timestamps as `timestamp without time zone` in PostgreSQL, with the convention that all values are UTC. The Ecto schema loads them as `DateTime` structs with `time_zone: "Etc/UTC"`. Timezone conversion for display is handled at the presentation layer (LiveView templates).
