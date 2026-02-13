# ADR-001: Phoenix + Standard Ecto over Ash Framework

**Status**: Accepted
**Date**: 2025-12-16
**Deciders**: Project Lead
**Context**: Sound Forge Alchemy port from Node.js/TypeScript + React to Elixir/OTP

## Context

Sound Forge Alchemy is being ported from a Node.js/TypeScript backend with Express, Redis job queues, and a React frontend to an Elixir/OTP stack. The application has a focused domain: ingest Spotify URLs, download audio, run ML-based analysis (librosa) and stem separation (demucs), and present results through a real-time web interface.

The decision concerns which Elixir web framework and data layer to use for this port.

## Decision

Use **Phoenix 1.8 with LiveView** for the web layer and **standard Ecto** for the data layer. Do not use the Ash Framework.

## Rationale

### 1. Focused Domain, Not a CRUD Platform

Sound Forge Alchemy has approximately 6 database tables (tracks, download_jobs, processing_jobs, analysis_jobs, stems, analysis_results) with well-defined relationships. The primary complexity is in the background processing pipeline (Oban workers coordinating external tools), not in the data modeling layer. Standard Ecto contexts (`SoundForge.Music`, `SoundForge.Spotify`, `SoundForge.Storage`) provide clean boundaries without additional abstraction.

### 2. Simpler Mental Model for Porting

The original Node.js codebase uses Express routes, Sequelize models, and direct database queries. These map directly to Phoenix controllers, Ecto schemas, and Repo calls. Introducing Ash's declarative resource DSL, action system, and policy layer would require learning a new paradigm during the port -- adding risk and schedule pressure with no proportional benefit.

### 3. Existing Team Knowledge

The development workflow uses standard Phoenix patterns documented in `AGENTS.md`: contexts with `Repo.all/1`, `Repo.insert/1`, `Repo.update/1`; changesets for validation; LiveView for real-time UI. These are well-understood, heavily documented, and have extensive community examples. Ash Framework has a smaller ecosystem and fewer debugging resources.

### 4. Lower Abstraction Overhead

Ash provides declarative resource definitions, computed attributes, actions, policies, and multi-tenancy. Sound Forge Alchemy needs none of these. The Oban integration, Port management, and PubSub broadcasting are custom behaviors that do not fit naturally into Ash's action system. Adding Ash would mean fighting the framework where the domain diverges from CRUD.

### 5. Direct Control Over Job Pipeline

The audio processing pipeline (download -> process -> analyze) requires fine-grained control over Oban job insertion, status tracking, progress broadcasting, and file cleanup. Standard Ecto operations and direct Oban.Worker implementations give full control over this pipeline without indirection through Ash actions or notifiers.

## Alternatives Considered

### Ash Framework

**What it offers**: Declarative resource modeling, built-in CRUD actions, policy authorization, API generation (JSON:API, GraphQL), computed attributes, multi-tenancy, and a plugin ecosystem.

**Why rejected**:

- **Complexity cost**: Ash introduces its own DSL, action system, and data layer abstraction. For 6 tables with straightforward relationships, this is overhead without benefit.
- **Pipeline mismatch**: The core complexity is in background processing (Oban workers, Port communication, PubSub broadcasting), not in data access patterns. Ash optimizes for the latter.
- **Debugging difficulty**: When something goes wrong in an Ash resource pipeline, the stack trace passes through multiple layers of Ash internals. Standard Ecto errors point directly to the query or changeset.
- **Port/Oban integration**: Ash's action system does not have built-in support for Erlang Ports or Oban job orchestration. These would need to be custom extensions, negating the "declarative" benefit.
- **Community size**: Fewer StackOverflow answers, fewer blog posts, fewer examples to reference during development.

## Consequences

### Positive

- Direct, transparent data access through Ecto queries and changesets
- Full control over the Oban job pipeline without framework indirection
- Standard Phoenix patterns that match all community documentation
- Simpler onboarding for any Elixir developer familiar with Phoenix
- Debugging goes straight to Ecto/Repo/Oban without framework internals

### Negative

- No declarative API generation (JSON:API endpoints must be hand-written)
- No built-in authorization policies (must be implemented manually if needed)
- Boilerplate in context modules (standard CRUD functions like `list_tracks/0`, `get_track!/1`)
- If the domain grows significantly (multi-tenant, fine-grained permissions), revisiting this decision may be necessary

### Neutral

- Migration path to Ash exists if needed: Ecto schemas can be gradually wrapped in Ash resources
- Phoenix 1.8 LiveView provides real-time UI that Ash's API generation does not replace
