---
title: Configuration
parent: Guides
nav_order: 3
---

[Home](../index.md) > [Guides](index.md) > Configuration

# Configuration

All environment variables and configuration options for Sound Forge Alchemy.

## Table of Contents

- [User Settings Panel](#user-settings-panel)
- [Environment Variable Reference](#environment-variable-reference)
- [Required Variables](#required-variables)
- [Optional Variables](#optional-variables)
- [LLM Provider Variables](#llm-provider-variables)
- [Production Variables](#production-variables)
- [Encryption Configuration](#encryption-configuration)
- [Oban Configuration](#oban-configuration)
- [Config File Reference](#config-file-reference)

---

## User Settings Panel

The Settings page (accessible after login at `/settings`) provides a UI for all per-user configuration. The sidebar lists every category available:

![User Settings panel showing Spotify integration and tool availability](../assets/screenshots/settings-authenticated.png)
*Settings panel: Spotify Connected status (green dot), SpotDL and FFmpeg tool availability indicators, and full sidebar with 10 configuration categories.*

---

## Environment Variable Reference

SFA loads `.env` automatically in development and test via `config/runtime.exs`. In production, set variables in your container environment or secrets manager.

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SPOTIFY_CLIENT_ID` | Spotify app client ID | `abc123def456` |
| `SPOTIFY_CLIENT_SECRET` | Spotify app client secret | `xyz789...` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `4000` | HTTP server port |
| `LALALAI_API_KEY` | — | lalal.ai user API key (enables cloud separation) |
| `SYSTEM_LALALAI_ACTIVATION_KEY` | — | lalal.ai system activation key |
| `LLM_ENCRYPTION_KEY` | Derived from `SECRET_KEY_BASE` | Base64-encoded 32-byte key for encrypting LLM provider API keys at rest |

### LLM Provider Variables

System-level LLM provider fallbacks. If set, they are available to all users without per-user configuration.

| Variable | Provider |
|----------|---------|
| `ANTHROPIC_API_KEY` | Anthropic Claude |
| `OPENAI_API_KEY` | OpenAI GPT-4o / o3 |
| `GOOGLE_API_KEY` | Google Gemini |
| `OLLAMA_BASE_URL` | Ollama (default: `http://localhost:11434`) |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI endpoint URL |

### Production Variables

Required in production (`MIX_ENV=prod`):

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string: `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | 64+ character secret for session signing. Generate: `mix phx.gen.secret` |
| `PHX_HOST` | Public hostname (e.g., `sfa-app.example.com`) |
| `PHX_SERVER` | Set to `true` to enable the HTTP server in a release |

Optional production variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `POOL_SIZE` | `10` | Ecto database connection pool size |
| `ECTO_IPV6` | `false` | Enable IPv6 for database connection |
| `DATABASE_SSL` | `false` | Enable SSL for database connection |
| `DNS_CLUSTER_QUERY` | — | DNS query for distributed Erlang clustering |

---

## Encryption Configuration

SFA uses `Cloak.Ecto` for field-level encryption of LLM provider API keys and OAuth tokens.

Key resolution order:

1. `LLM_ENCRYPTION_KEY` environment variable (Base64-encoded 32 bytes)
2. Derived from `SECRET_KEY_BASE` via SHA-256

To generate a new encryption key:

```bash
# Generate 32 random bytes and Base64-encode
openssl rand -base64 32
```

**Warning:** Changing the encryption key will make all previously encrypted values unreadable. Store and back up this key securely.

The cipher configuration in `config/runtime.exs`:

```elixir
config :sound_forge, SoundForge.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: vault_key,   # 32-byte binary
      iv_length: 12
    }
  ]
```

---

## Oban Configuration

Background job queues configured in `config/config.exs`:

```elixir
config :sound_forge, Oban,
  repo: SoundForge.Repo,
  queues: [download: 3, processing: 2, analysis: 2]
```

| Queue | Concurrency | Notes |
|-------|-------------|-------|
| `download` | 3 | Network-bound; safe to run 3 concurrent |
| `processing` | 2 | GPU/CPU-bound; Demucs uses 2–4 GB per instance |
| `analysis` | 2 | CPU-bound; lighter than Demucs |

To adjust concurrency at runtime (via Oban Pro or custom implementation):

```elixir
Oban.scale_queue(:download, limit: 5)
```

---

## Config File Reference

### `config/config.exs`

Compile-time configuration. Sets up Ecto, Oban, Swoosh, and asset pipelines.

### `config/dev.exs`

Development overrides: live reload, debug logging, `phx.gen.auth` dev routes, local file watcher.

### `config/test.exs`

Test overrides: synchronous Oban (`testing: :inline`), mock Spotify client (`SoundForge.Spotify.MockClient`), test database.

### `config/runtime.exs`

Runtime configuration loaded at application start. Sources environment variables for Spotify credentials, lalal.ai keys, encryption keys, and all production settings.

Key runtime behaviors:

```elixir
# Load .env in dev/test automatically
if config_env() in [:dev, :test] do
  env_file = Path.join(File.cwd!(), ".env")
  # ... line-by-line .env parsing
end

# Configure Spotify from env
config :sound_forge, :spotify,
  client_id: System.get_env("SPOTIFY_CLIENT_ID"),
  client_secret: System.get_env("SPOTIFY_CLIENT_SECRET")

# Configure lalal.ai
config :sound_forge, :lalalai_api_key, System.get_env("LALALAI_API_KEY")

# Production-only: require DATABASE_URL and SECRET_KEY_BASE
if config_env() == :prod do
  database_url = System.get_env("DATABASE_URL") || raise "DATABASE_URL missing"
  secret_key_base = System.get_env("SECRET_KEY_BASE") || raise "SECRET_KEY_BASE missing"
  # ...
end
```

---

## .env File Template

```bash
# =============================================
# Sound Forge Alchemy — Environment Variables
# =============================================

# --- Required ---
SPOTIFY_CLIENT_ID=
SPOTIFY_CLIENT_SECRET=

# --- Optional Features ---
LALALAI_API_KEY=
SYSTEM_LALALAI_ACTIVATION_KEY=

# --- LLM Providers (system-level fallbacks) ---
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
GOOGLE_API_KEY=
OLLAMA_BASE_URL=http://localhost:11434

# --- Encryption ---
# LLM_ENCRYPTION_KEY=   # Leave unset in dev (derived from SECRET_KEY_BASE)

# --- Production Only ---
# DATABASE_URL=ecto://user:pass@host/db
# SECRET_KEY_BASE=
# PHX_HOST=sfa-app.example.com
# PHX_SERVER=true
# POOL_SIZE=10
```

---

## See Also

- [Installation Guide](installation.md)
- [Deployment Guide](deployment.md)
- [LLM Providers Architecture](../architecture/llm-providers.md)

---

[← Installation](installation.md) | [Next: Deployment →](deployment.md)
