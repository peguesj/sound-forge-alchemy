---
title: Tech Stack
parent: Architecture
nav_order: 1
---

[Home](../index.md) > [Architecture](index.md) > Tech Stack

# Tech Stack

## Table of Contents

- [Backend (Elixir/OTP)](#backend-elixirotp)
- [Frontend (Phoenix Templates)](#frontend-phoenix-templates)
- [Audio Processing (Python)](#audio-processing-python)
- [Database](#database)
- [Background Jobs](#background-jobs)
- [Infrastructure](#infrastructure)
- [Key Dependencies](#key-dependencies)

---

## Backend (Elixir/OTP)

| Technology | Version | Purpose |
|-----------|---------|---------|
| Elixir | ~> 1.15 | Application language |
| Phoenix | ~> 1.8.3 | Web framework |
| Phoenix LiveView | ~> 1.1.0 | Real-time UI without JavaScript SPA |
| Bandit | ~> 1.5 | HTTP server (replaces Cowboy) |
| Ecto | ~> 3.13 | Database ORM |
| Oban | ~> 2.18 | Background job processing |
| Req | ~> 0.5 | HTTP client (Spotify API, lalal.ai API) |
| Cloak.Ecto | ~> 1.3 | At-rest encryption (API keys, tokens) |
| Midiex | ~> 0.6 | MIDI device interface |
| Swoosh | ~> 1.16 | Transactional email |
| Gettext | ~> 1.0 | Internationalization |
| Jason | ~> 1.2 | JSON encoding/decoding |
| dns_cluster | ~> 0.2.0 | Distributed Erlang clustering |

### Why Phoenix 1.8

Phoenix 1.8 introduces colocated JS hooks (`:type={Phoenix.LiveView.ColocatedHook}`), a new Tailwind v4 CSS pipeline, and improved `phx.gen.auth` with scope-based authentication. SFA uses all three.

### Why Oban (Not Redis + BullMQ)

The TypeScript predecessor used BullMQ on Redis. Oban provides equivalent functionality using the existing PostgreSQL database:
- Jobs inserted in the same transaction as their domain records — no orphans
- LISTEN/NOTIFY for real-time dispatch (no polling)
- Configurable per-queue concurrency: `download: 3, processing: 2, analysis: 2`
- Built-in retry with configurable `max_attempts`

### Why Erlang Ports (Not NIFs)

Demucs (PyTorch) and librosa (NumPy/SciPy) are mature Python libraries with no Elixir equivalents. Ports run them as supervised OS processes:
- A Python crash cannot take down the BEAM VM
- Long-running operations (seconds to minutes) — unsuitable as NIFs
- No HTTP overhead — communication over OS pipes (stdin/stdout)

---

## Frontend (Phoenix Templates)

| Technology | Version | Purpose |
|-----------|---------|---------|
| Phoenix HEEx | 1.8 | Server-rendered HTML templates |
| Tailwind CSS | v4 | Utility-first CSS (no tailwind.config.js) |
| daisyUI | 4.x | Component library base |
| esbuild | ~> 0.10 | JavaScript bundling |
| D3.js | 7.x | Audio analysis visualizations |
| Heroicons | v2.2.0 | SVG icon system |

### D3.js Hooks

Five Phoenix JS hooks render audio analysis data as interactive SVG charts:

| Hook | Visualization |
|------|--------------|
| `AnalysisRadar` | Spider/radar chart of feature scores |
| `AnalysisChroma` | 12-bin chromagram (pitch class energy) |
| `AnalysisBeats` | Beat grid timeline |
| `AnalysisMFCC` | MFCC coefficient heatmap |
| `AnalysisSpectral` | Spectral centroid + rolloff line chart |

---

## Audio Processing (Python)

| Technology | Purpose |
|-----------|---------|
| Demucs (htdemucs, htdemucs_ft, htdemucs_6s, mdx_extra) | Local stem separation (PyTorch) |
| librosa | Audio feature extraction (tempo, key, energy, MFCC, chroma, spectral) |
| spotdl | Spotify audio download (YouTube source + metadata) |
| lalal.ai API | Cloud stem separation (9+ stem types, 60s preview) |

### Demucs Models

| Model | Stems | Quality | Speed |
|-------|-------|---------|-------|
| `htdemucs` | 4 (vocals, drums, bass, other) | Good | Fast |
| `htdemucs_ft` | 4 | High | Slow |
| `htdemucs_6s` | 6 (+ guitar, piano) | Good | Medium |
| `mdx_extra` | 4 | High for vocals | Medium |

### Python Erlang Port Protocol

Communication uses newline-delimited JSON over stdin/stdout:

```json
// DemucsPort progress message
{"type": "progress", "percent": 45}

// DemucsPort result message
{"type": "result", "stems": {"vocals": "/path/vocals.wav", "drums": "/path/drums.wav"}}

// AnalyzerPort result message
{"tempo": 120.5, "key": "C major", "energy": 0.74, "spectral_centroid": 1823.4}
```

---

## Database

| Technology | Version | Purpose |
|-----------|---------|---------|
| PostgreSQL | 14+ | Primary data store |
| Ecto | ~> 3.13 | ORM and migrations |
| Postgrex | latest | PostgreSQL driver |
| Oban | ~> 2.18 | Job queue tables |

All primary keys are `binary_id` (UUID v4). See [Database Schema](database.md) for full schema.

---

## Background Jobs

| Queue | Concurrency | Worker | Purpose |
|-------|-------------|--------|---------|
| `download` | 3 | `DownloadWorker` | `spotdl` audio downloads |
| `processing` | 2 | `ProcessingWorker` | Demucs stem separation |
| `analysis` | 2 | `AnalysisWorker` | librosa feature extraction |

Additional workers: `LalalaiWorker`, `AutoCueWorker`, `ChefWorker`, `CleanupWorker`, `MultistemWorker`, `ProviderHealthWorker`, `VoiceChangeWorker`, `VoiceCleanWorker`.

---

## Infrastructure

| Service | Purpose |
|---------|---------|
| Azure Container Apps | Production hosting |
| Azure Container Registry | Docker image storage |
| Azure PostgreSQL Flexible Server | Managed database |
| Docker (multi-stage) | Build + deployment |
| GitHub Actions | CI/CD pipeline |

### Docker Build Notes

- BEAM VM cannot run under QEMU on Apple Silicon — always use `az acr build` for remote amd64 builds
- ACR build does not support ARG interpolation in FROM directives — hardcode image refs
- Image is ~4.8GB due to Python deps (Demucs, librosa, spotdl)

---

## Key Dependencies

```elixir
# mix.exs (abbreviated)
defp deps do
  [
    {:bcrypt_elixir, "~> 3.0"},        # Password hashing
    {:phoenix, "~> 1.8.3"},
    {:phoenix_ecto, "~> 4.5"},
    {:ecto_sql, "~> 3.13"},
    {:postgrex, ">= 0.0.0"},
    {:phoenix_html, "~> 4.1"},
    {:phoenix_live_view, "~> 1.1.0"},
    {:phoenix_live_dashboard, "~> 0.8.3"},
    {:esbuild, "~> 0.10"},
    {:tailwind, "~> 0.3"},
    {:swoosh, "~> 1.16"},
    {:req, "~> 0.5"},
    {:oban, "~> 2.18"},
    {:midiex, "~> 0.6"},
    {:cloak_ecto, "~> 1.3"},
    {:credo, "~> 1.7"},
    {:dialyxir, "~> 1.4"}
  ]
end
```

---

## See Also

- [Architecture Overview](index.md)
- [Agent System](agents.md)
- [LLM Providers](llm-providers.md)
- [Installation Guide](../guides/installation.md)

---

[← Architecture Overview](index.md) | [Next: Agent System →](agents.md)
