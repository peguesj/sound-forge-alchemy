---
title: Database Schema
parent: Architecture
nav_order: 4
---

[Home](../index.md) > [Architecture](index.md) > Database Schema

# Database Schema

## Table of Contents

- [Overview](#overview)
- [Entity Relationships](#entity-relationships)
- [Core Tables](#core-tables)
- [Job Tables](#job-tables)
- [LLM Provider Table](#llm-provider-table)
- [Auth Tables](#auth-tables)
- [Oban Jobs Table](#oban-jobs-table)
- [Indexes and Constraints](#indexes-and-constraints)
- [Migration Strategy](#migration-strategy)

---

## Overview

Sound Forge Alchemy uses PostgreSQL 14+ with Ecto 3.13. All primary keys are `binary_id` (UUID v4). Oban uses the same database for job storage, writing to `oban_jobs`. API keys and OAuth tokens are encrypted at rest using `SoundForge.Vault` (AES-256-GCM via `Cloak.Ecto`).

---

## Entity Relationships

```
tracks
  |--- 1:N --- download_jobs
  |--- 1:N --- processing_jobs
  |                |--- 1:N --- stems
  |--- 1:N --- analysis_jobs
  |                |--- 1:1 --- analysis_results
  |--- 1:N --- stems          (direct FK for efficient queries)
  |--- 1:N --- analysis_results (direct FK for efficient queries)

users
  |--- 1:N --- llm_providers
  |--- 1:N --- download_jobs  (via user_id)
  |--- 1:N --- processing_jobs
  |--- 1:N --- analysis_jobs
  |--- 1:N --- tracks
```

---

## Core Tables

### `tracks`

The root entity. Represents a single piece of audio, typically sourced from Spotify.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, not null | UUID v4 primary key |
| `spotify_id` | `varchar` | unique | Spotify track identifier |
| `spotify_url` | `varchar` | — | Full Spotify URL |
| `title` | `varchar` | **required** | Track title |
| `artist` | `varchar` | — | Primary artist name |
| `album` | `varchar` | — | Album name |
| `album_art_url` | `varchar` | — | URL to album artwork |
| `duration` | `integer` | — | Duration in seconds |
| `user_id` | `uuid` | FK → users | Owning user |
| `inserted_at` | `timestamp` | not null | Creation time (UTC) |
| `updated_at` | `timestamp` | not null | Last modified (UTC) |

### `stems`

Individual audio stem files produced by processing jobs.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, not null | UUID v4 primary key |
| `processing_job_id` | `uuid` | FK, **required** | Parent ProcessingJob |
| `track_id` | `uuid` | FK, **required** | Parent Track |
| `stem_type` | `varchar` | enum, **required** | `vocals`, `drums`, `bass`, `other`, `guitar`, `piano` |
| `file_path` | `varchar` | — | Relative filesystem path |
| `file_size` | `integer` | — | File size in bytes |
| `inserted_at` | `timestamp` | not null | Creation time (UTC) |
| `updated_at` | `timestamp` | not null | Last modified (UTC) |

### `analysis_results`

Structured audio feature analysis output.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, not null | UUID v4 primary key |
| `track_id` | `uuid` | FK, **required** | Parent Track |
| `analysis_job_id` | `uuid` | FK, **required** | Parent AnalysisJob |
| `tempo` | `float` | — | BPM (beats per minute) |
| `key` | `varchar` | — | Musical key, e.g., `"C major"` |
| `energy` | `float` | — | Normalized RMS energy (0.0–1.0) |
| `spectral_centroid` | `float` | — | Spectral centroid in Hz |
| `spectral_rolloff` | `float` | — | Spectral rolloff in Hz |
| `zero_crossing_rate` | `float` | — | Zero crossing rate (0.0–1.0) |
| `features` | `jsonb` | — | Extended features (MFCC, chroma, etc.) |
| `inserted_at` | `timestamp` | not null | Creation time (UTC) |
| `updated_at` | `timestamp` | not null | Last modified (UTC) |

---

## Job Tables

All job tables share the same status state machine: `:queued` → `:downloading`/`:processing` → `:completed` | `:failed`.

### `download_jobs`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, not null | UUID v4 primary key |
| `track_id` | `uuid` | FK, **required** | Parent Track |
| `user_id` | `uuid` | FK | Owning user |
| `status` | `varchar` | enum, default: `queued` | `queued`, `downloading`, `processing`, `completed`, `failed` |
| `progress` | `integer` | default: 0, 0–100 | Completion percentage |
| `output_path` | `varchar` | — | Path to downloaded audio file |
| `file_size` | `integer` | — | Downloaded file size in bytes |
| `error` | `text` | — | Error message on failure |
| `inserted_at` | `timestamp` | not null | |
| `updated_at` | `timestamp` | not null | |

### `processing_jobs`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, not null | |
| `track_id` | `uuid` | FK, **required** | Parent Track |
| `user_id` | `uuid` | FK | Owning user |
| `model` | `varchar` | default: `htdemucs` | Demucs model or `lalalai` |
| `engine` | `varchar` | — | `local` or `lalalai` |
| `status` | `varchar` | enum, default: `queued` | `queued`, `downloading`, `processing`, `completed`, `failed` |
| `progress` | `integer` | default: 0, 0–100 | |
| `output_path` | `varchar` | — | Directory containing stem files |
| `options` | `jsonb` | — | Additional processing options |
| `error` | `text` | — | Error message on failure |
| `inserted_at` | `timestamp` | not null | |
| `updated_at` | `timestamp` | not null | |

### `analysis_jobs`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, not null | |
| `track_id` | `uuid` | FK, **required** | Parent Track |
| `user_id` | `uuid` | FK | Owning user |
| `status` | `varchar` | enum, default: `queued` | `queued`, `downloading`, `processing`, `completed`, `failed` |
| `progress` | `integer` | default: 0, 0–100 | |
| `results` | `jsonb` | — | Inline results |
| `error` | `text` | — | Error message on failure |
| `inserted_at` | `timestamp` | not null | |
| `updated_at` | `timestamp` | not null | |

---

## LLM Provider Table

### `llm_providers`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, not null | |
| `user_id` | `uuid` | FK, **required** | Owning user |
| `provider_type` | `varchar` | enum, **required** | `anthropic`, `openai`, `google_gemini`, `ollama`, `azure_openai` |
| `name` | `varchar` | **required** | Display name |
| `api_key` | `bytea` | encrypted | Cloak.Ecto AES-256-GCM |
| `enabled` | `boolean` | default: true | Whether active |
| `priority` | `integer` | default: 0 | Provider preference order |
| `health_status` | `varchar` | default: `unknown` | `healthy`, `unreachable`, `unknown` |
| `last_health_check_at` | `timestamp` | — | Last health check timestamp |
| `inserted_at` | `timestamp` | not null | |
| `updated_at` | `timestamp` | not null | |

---

## Auth Tables

Generated by `phx.gen.auth`. Uses scope-based authentication.

### `users`

| Column | Type | Description |
|--------|------|-------------|
| `id` | `uuid` | PK |
| `email` | `varchar` | Unique, required |
| `hashed_password` | `varchar` | bcrypt hash |
| `role` | `varchar` | `user`, `admin`, `platform_admin` |
| `confirmed_at` | `timestamp` | Email confirmation timestamp |
| `inserted_at` | `timestamp` | |
| `updated_at` | `timestamp` | |

### `users_tokens`

| Column | Type | Description |
|--------|------|-------------|
| `id` | `uuid` | PK |
| `user_id` | `uuid` | FK → users |
| `token` | `bytea` | Secure token bytes |
| `context` | `varchar` | `session`, `confirm`, `reset_password` |
| `sent_to` | `varchar` | Email address (for email tokens) |
| `inserted_at` | `timestamp` | |

---

## Oban Jobs Table

Managed by Oban migrations. Not manually edited.

### `oban_jobs`

Key columns:

| Column | Description |
|--------|-------------|
| `id` | bigserial PK |
| `queue` | Queue name: `download`, `processing`, `analysis` |
| `state` | `available`, `scheduled`, `executing`, `retryable`, `completed`, `discarded`, `cancelled` |
| `worker` | Module name string (e.g., `"SoundForge.Jobs.DownloadWorker"`) |
| `args` | jsonb — worker arguments |
| `errors` | jsonb array — per-attempt error records |
| `attempt` | Current attempt number |
| `max_attempts` | Maximum retry attempts |
| `inserted_at` | |
| `scheduled_at` | When job should run |
| `attempted_at` | Last attempt timestamp |
| `completed_at` | Completion timestamp |

---

## Indexes and Constraints

Key indexes beyond primary keys:

| Table | Index | Type | Purpose |
|-------|-------|------|---------|
| `tracks` | `spotify_id` | unique | Prevents duplicate imports |
| `stems` | `(track_id, stem_type)` | index | Stem queries by track |
| `stems` | `processing_job_id` | index | Stems by job |
| `analysis_results` | `track_id` | index | Results by track |
| `llm_providers` | `(user_id, priority)` | index | Provider ordering |
| `oban_jobs` | `(queue, state, priority)` | index | Job dispatch |

---

## Migration Strategy

```bash
# Generate a new migration
mix ecto.gen.migration add_feature_name

# Run migrations
mix ecto.migrate

# Reset database (dev only)
mix ecto.reset

# Check current schema version
mix ecto.migrations
```

Migration files live in `priv/repo/migrations/`. Each is timestamped and idempotent. Production deployments apply migrations before the application starts via the `Release` module:

```elixir
# lib/sound_forge/release.ex
def migrate do
  load_app()
  for repo <- repos() do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
  end
end
```

---

## See Also

- [Domain Model Architecture Docs](../../docs/architecture/01_DOMAIN_MODEL.md)
- [Architecture Overview](index.md)
- [Configuration Guide](../guides/configuration.md)

---

[← LLM Providers](llm-providers.md) | [Next: Guides →](../guides/index.md)
