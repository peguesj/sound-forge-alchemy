---
title: LLM Providers
parent: Architecture
nav_order: 3
---

[Home](../index.md) > [Architecture](index.md) > LLM Providers

# LLM Providers

## Table of Contents

- [Overview](#overview)
- [Supported Providers](#supported-providers)
- [Model Registry](#model-registry)
- [Provider Configuration](#provider-configuration)
- [Model Selection Logic](#model-selection-logic)
- [Health Checks](#health-checks)
- [System vs User Providers](#system-vs-user-providers)

---

## Overview

Sound Forge Alchemy uses a pluggable LLM adapter architecture. Users can configure their own API keys for any supported provider, or the system can fall back to server-level environment variable keys.

All provider records are stored in PostgreSQL, encrypted at rest using `Cloak.Ecto` (AES-256-GCM). The `ModelRegistry` GenServer seeds known model capabilities into ETS on startup and runs 5-minute health checks.

---

## Supported Providers

| Provider | Type Atom | Models |
|---------|-----------|--------|
| Anthropic | `:anthropic` | claude-opus-4-6, claude-sonnet-4-20250514, claude-haiku-4-5-20251001 |
| OpenAI | `:openai` | gpt-4o, gpt-4o-mini, o3 |
| Google Gemini | `:google_gemini` | gemini-2.0-flash, gemini-2.5-pro |
| Ollama (local) | `:ollama` | llama3.2, mistral, codellama |
| Azure OpenAI | `:azure_openai` | gpt-4o |

---

## Model Registry

**Module:** `SoundForge.LLM.ModelRegistry`

A `GenServer`-backed registry with ETS storage. Tracks known model capabilities including speed, quality, cost, context window, and supported features.

### Model Capability Schema

```elixir
%{
  provider_type: :anthropic,
  model: "claude-opus-4-6",
  speed: :slow,          # :fast | :medium | :slow
  quality: :high,        # :high | :medium | :low
  cost: :high,           # :free | :low | :medium | :high
  context_window: 200_000,
  features: [:chat, :vision, :tool_use, :json_mode]
}
```

### Full Model List

| Provider | Model | Speed | Quality | Cost | Context | Features |
|---------|-------|-------|---------|------|---------|---------|
| Anthropic | claude-opus-4-6 | slow | high | high | 200k | chat, vision, tool_use, json_mode |
| Anthropic | claude-sonnet-4-20250514 | medium | high | medium | 200k | chat, vision, tool_use, json_mode |
| Anthropic | claude-haiku-4-5-20251001 | fast | medium | low | 200k | chat, vision, tool_use, json_mode |
| OpenAI | gpt-4o | medium | high | medium | 128k | chat, vision, tool_use, json_mode, audio |
| OpenAI | gpt-4o-mini | fast | medium | low | 128k | chat, vision, tool_use, json_mode |
| OpenAI | o3 | slow | high | high | 128k | chat, tool_use, json_mode |
| Google Gemini | gemini-2.0-flash | fast | medium | low | 1M | chat, vision, tool_use, json_mode, audio |
| Google Gemini | gemini-2.5-pro | medium | high | medium | 1M | chat, vision, tool_use, json_mode, audio |
| Ollama | llama3.2 | medium | medium | free | 128k | chat, tool_use |
| Ollama | mistral | fast | medium | free | 32k | chat |
| Ollama | codellama | medium | medium | free | 16k | chat |
| Azure OpenAI | gpt-4o | medium | high | medium | 128k | chat, vision, tool_use, json_mode |

### Public API

```elixir
# List all known models
ModelRegistry.list_models()

# Get models supporting specific features
ModelRegistry.models_for_task([:chat, :vision])

# Find best model for a task
ModelRegistry.best_model_for(:analysis, prefer: :speed)
ModelRegistry.best_model_for(:chat, prefer: :quality, provider_types: [:anthropic])

# Get specific model capabilities
ModelRegistry.get_model(:anthropic, "claude-opus-4-6")

# Trigger health check for a user's providers
ModelRegistry.check_health(user_id)
```

### Selection Preferences

| Preference | Strategy |
|-----------|---------|
| `:quality` (default) | Maximize quality score: high=3, medium=2, low=1 |
| `:speed` | Minimize speed score: fast=0, medium=1, slow=2 |
| `:cost` | Minimize cost score: free=0, low=1, medium=2, high=3 |

---

## Provider Configuration

**Module:** `SoundForge.LLM.Provider` (Ecto schema)
**Context:** `SoundForge.LLM.Providers`

Providers are stored as encrypted database records per user:

| Field | Type | Description |
|-------|------|-------------|
| `id` | `binary_id` | UUID primary key |
| `user_id` | `binary_id` | Owning user |
| `provider_type` | enum | `:anthropic`, `:openai`, `:google_gemini`, `:ollama`, `:azure_openai` |
| `name` | string | User-defined display name |
| `api_key` | encrypted string | Encrypted at rest via Cloak.Ecto |
| `enabled` | boolean | Whether provider is active |
| `priority` | integer | Order in provider preference list |
| `health_status` | enum | `:healthy`, `:unreachable`, `:unknown` |
| `last_health_check_at` | datetime | Timestamp of last health check |

### Context Operations

```elixir
# List all providers for a user (ordered by priority)
Providers.list_providers(user_id)

# Get only enabled providers
Providers.get_enabled_providers(user_id)

# Create a new provider
Providers.create_provider(user_id, %{
  provider_type: :anthropic,
  name: "My Claude",
  api_key: "sk-ant-..."
})

# Toggle enabled state
Providers.toggle_provider(provider)
Providers.toggle_provider(provider, true)

# Reorder providers (bulk priority update)
Providers.reorder_providers(user_id, [{id1, 0}, {id2, 1}])

# Get all available: DB records + system env fallbacks
Providers.all_available_providers(user_id)
```

---

## Model Selection Logic

The `ModelRegistry.best_model_for/2` function:

1. Collect all models matching required features via `models_for_task/1`
2. If `provider_types` option supplied, filter to those provider types
3. Apply preference scoring:
   - `:speed` → `Enum.min_by(speed_score/1)`
   - `:cost` → `Enum.min_by(cost_score/1)`
   - `:quality` (default) → `Enum.max_by(quality_score/1)`
4. Return the best candidate, or `nil` if no models match

Task-to-feature mapping:

| Task | Required Features |
|------|------------------|
| `:chat` | `[:chat]` |
| `:analysis` | `[:chat, :json_mode]` |
| `:vision` | `[:chat, :vision]` |
| `:tool_use` | `[:chat, :tool_use]` |

---

## Health Checks

The `ModelRegistry` schedules a health check every 5 minutes (`:timer.minutes(5)`):

1. System providers — loaded from environment variables, checked on a schedule, status logged
2. User providers — checked on demand via `ModelRegistry.check_health(user_id)`, status persisted to database

Health check implementation uses `SoundForge.LLM.Client.test_connection/1`, which sends a minimal ping request to the provider's API.

---

## System vs User Providers

**System providers** are read from environment variables on startup:

| Env Var | Provider Type |
|---------|--------------|
| `ANTHROPIC_API_KEY` | `:anthropic` |
| `OPENAI_API_KEY` | `:openai` |
| `GOOGLE_API_KEY` | `:google_gemini` |
| `OLLAMA_BASE_URL` | `:ollama` (default: `http://localhost:11434`) |
| `AZURE_OPENAI_API_KEY` + `AZURE_OPENAI_ENDPOINT` | `:azure_openai` |

System providers are ephemeral — they are not persisted to the database. They are available as fallbacks when a user has not configured a provider of that type.

**User providers** are persisted to PostgreSQL with encrypted API keys. When `Providers.all_available_providers/1` is called:
- DB records are returned first (ordered by priority)
- System providers not covered by the user's DB records are appended

---

## See Also

- [Agent System](agents.md)
- [Configuration Guide](../guides/configuration.md)
- [AI Agents Feature](../features/ai-agents.md)

---

[← Agent System](agents.md) | [Next: Database Schema →](database.md)
