---
title: Quickstart
parent: Guides
nav_order: 1
---

[Home](../index.md) > [Guides](index.md) > Quickstart

# Quickstart

Get Sound Forge Alchemy running locally in about 5 minutes.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1: Clone and Install](#step-1-clone-and-install)
- [Step 2: Configure Environment](#step-2-configure-environment)
- [Step 3: Start the Database](#step-3-start-the-database)
- [Step 4: Run the App](#step-4-run-the-app)
- [Step 5: Import Your First Track](#step-5-import-your-first-track)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

You must have installed:

- **Elixir** ~> 1.15 and **Erlang/OTP** 26+ (`brew install elixir` on macOS)
- **PostgreSQL** 14+ running locally or accessible via `DATABASE_URL`
- **Node.js** 20+ for asset compilation
- **Python** 3.10+ with `pip`
- A **Spotify Developer** account with a registered application

Optional but recommended:
- **spotdl** for audio downloads: `pip install spotdl`
- **demucs** for local stem separation: `pip install demucs`
- **librosa** for audio analysis: `pip install librosa`

---

## Step 1: Clone and Install

```bash
git clone https://github.com/peguesj/sound-forge-alchemy.git
cd sound-forge-alchemy

# Install Elixir dependencies
mix deps.get

# Install JS dependencies
npm install

# Set up assets
mix assets.setup
```

---

## Step 2: Configure Environment

Create a `.env` file in the project root:

```bash
cp .env.example .env   # if example exists, or create manually
```

Minimum required variables:

```bash
# .env

# Spotify OAuth (required for track import)
SPOTIFY_CLIENT_ID=your_spotify_client_id
SPOTIFY_CLIENT_SECRET=your_spotify_client_secret

# Database (uses local dev defaults if omitted)
# DATABASE_URL=ecto://postgres:postgres@localhost/sound_forge_dev
```

See the [Configuration Guide](configuration.md) for all available variables.

---

## Step 3: Start the Database

```bash
# Create and migrate the database
mix ecto.setup
```

This runs `ecto.create`, `ecto.migrate`, and `priv/repo/seeds.exs`.

---

## Step 4: Run the App

```bash
# Source .env and start the server
source .env && mix phx.server
```

The application starts at [http://localhost:4000](http://localhost:4000).

Register an account at `/users/register`.

---

## Step 5: Import Your First Track

1. Open [http://localhost:4000](http://localhost:4000)
2. Log in with your account
3. Paste a Spotify track URL (e.g., `https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC`)
4. Click **Import**
5. Watch the download, stem separation, and analysis pipeline run in real time

---

## Troubleshooting

### `DATABASE_URL` missing error
Ensure PostgreSQL is running and `ecto.create` succeeded. For local dev, the default URL is `ecto://postgres:postgres@localhost/sound_forge_dev`.

### `SPOTIFY_CLIENT_ID` missing
The app will load but Spotify import will fail. Set both `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET` in `.env`.

### `spotdl` not found
Downloads require `spotdl` on the system PATH. Install with `pip install spotdl`. If using Docker, it is included in the image.

### Python analysis errors
Install `librosa` and its dependencies: `pip install librosa soundfile`. On Apple Silicon, also install `pip install llvmlite`.

---

## See Also

- [Full Installation Guide](installation.md)
- [Configuration Reference](configuration.md)
- [Development Setup](development.md)

---

[← Guides Index](index.md) | [Next: Installation →](installation.md)
