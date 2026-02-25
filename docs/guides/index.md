---
title: Guides
nav_order: 3
has_children: true
---

[Home](../index.md) > Guides

# Guides

Everything you need to install, configure, and operate Sound Forge Alchemy. Whether you are setting up a local development environment for the first time or deploying to Azure Container Apps, the guides below cover the full lifecycle.

---

## Recommended Reading Order

For a first-time setup, follow this sequence:

```
Installation → Quickstart → Development → Configuration → Deployment
```

1. **[Installation](installation.md)** — Install all system dependencies (Elixir, Erlang, Node, Python, PostgreSQL) and clone the repository.
2. **[Quickstart](quickstart.md)** — Get the application running in under 5 minutes using the minimal configuration.
3. **[Development](development.md)** — Configure your dev environment, run tests, use the DevTools panel, and understand the contribution workflow.
4. **[Configuration](configuration.md)** — Review every environment variable and runtime config option before enabling optional features.
5. **[Deployment](deployment.md)** — Build the Docker image, push to Azure Container Registry, and deploy to Azure Container Apps.

---

## Available Guides

### [Installation](installation.md)

Covers the complete prerequisite installation process for macOS, Linux, and WSL2. Walks through installing Elixir (via `asdf` or system package manager), Erlang/OTP 26+, Node.js 20+, PostgreSQL 14+, and the Python stack (Demucs, librosa, SpotDL). Also covers cloning the repository, running `mix setup`, and creating the development database. Use this guide when setting up a machine from scratch.

---

### [Quickstart](quickstart.md)

Gets the server running with only the essential configuration: a local PostgreSQL database, minimal `.env` with Spotify credentials, and `mix phx.server`. If you want to verify the core download and playback flow without configuring stem separation or AI agents, start here. This guide deliberately omits optional services (lalal.ai, LLM providers) to reduce setup friction.

---

### [Development](development.md)

Reference for day-to-day development work. Covers the dev server startup sequence (`source .env && PORT=4000 mix phx.server`), the floating DevTools panel accessible at `/prototype`, running the full test suite (`mix test`), writing and running Playwright E2E tests, using the UAT fixture helpers (`SoundForge.UAT`), and the log watcher script at `tmp/log_watcher.sh`. Also documents the role hierarchy and how to elevate a local dev account to `platform_admin`.

---

### [Configuration](configuration.md)

Documents every environment variable recognized by `config/runtime.exs`. Organized into sections: required variables (Spotify OAuth, database URL, secret key base), optional audio processing variables (lalal.ai API key, Demucs model selection), optional AI agent variables (LLM provider API keys), and production-only variables (PHX_HOST, Azure storage connection strings). Includes a sample `.env` file and notes on which variables require a server restart to take effect.

---

### [Deployment](deployment.md)

Walks through the Azure Container Apps deployment pipeline. Covers building the production Docker image via `az acr build` (required for Apple Silicon — QEMU cannot run BEAM), pushing to Azure Container Registry, configuring Container Apps environment variables, setting up the managed PostgreSQL instance, and performing a rolling update. Includes the live production URL and notes on the ~4.8 GB image size caused by Python audio dependencies. Also documents the `DOCKER_BUILDKIT` gotchas discovered during initial deployment.

---

## Prerequisites at a Glance

| Dependency | Minimum Version | Purpose |
|------------|----------------|---------|
| Elixir | ~> 1.15 | Application runtime |
| Erlang/OTP | 26+ | BEAM virtual machine |
| Node.js | 20+ | Asset pipeline (esbuild, Tailwind) |
| PostgreSQL | 14+ | Primary data store |
| Python | 3.10+ | Demucs, librosa, SpotDL |
| Docker | 24+ | Production image build |

---

## I Want To...

| Goal | Go To |
|------|-------|
| Run the app for the first time | [Quickstart](quickstart.md) |
| Install all dependencies from scratch | [Installation](installation.md) |
| Add a new environment variable | [Configuration](configuration.md) |
| Deploy to production on Azure | [Deployment](deployment.md) |
| Run the test suite | [Development](development.md#testing) |
| Use the DevTools / UAT panel | [Development](development.md#devtools) |
| Understand Spotify OAuth setup | [Configuration](configuration.md#spotify) |
| Enable lalal.ai stem separation | [Configuration](configuration.md#lalalai) |
| Enable AI agent LLM providers | [Configuration](configuration.md#llm-providers) |
| Contribute a pull request | [Development](development.md#contributing) |

---

## See Also

- [Architecture Overview](../architecture/index.md)
- [Configuration Reference](configuration.md)
- [API Reference](../api/index.md)

---

[Next: Quickstart →](quickstart.md)
