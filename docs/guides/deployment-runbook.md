# Deployment Runbook

**Application**: Sound Forge Alchemy (SFA)
**Stack**: Elixir/Phoenix
**Last reviewed**: 2026-03-30

This is the operator-focused runbook. For developer setup see `docs/guides/deployment.md`.

---

## 1. Overview

SFA runs in three modes via `WORKER_MODE` env var:

| Mode | Purpose |
|------|---------|
| `full` | Web + Oban workers (default) |
| `web` | Web only — no workers |
| `gpu_worker` | Headless GPU worker — no HTTP listener |

---

## 2. Prerequisites

| Tool | Version | Source |
|------|---------|--------|
| Elixir | 1.17.3 | `.tool-versions` |
| Erlang/OTP | 27.1 | `.tool-versions` |
| Node.js | 22.11.0 | `.tool-versions` |

```bash
asdf install
```

---

## 3. Environment Variables

| Variable | Required | Description |
|---|---|---|
| `SECRET_KEY_BASE` | Yes | 64-byte Phoenix secret. Generate: `mix phx.gen.secret` |
| `DATABASE_URL` | Yes | `ecto://user:pass@host/sfa_prod` |
| `PHX_HOST` | Yes (prod) | External hostname for LiveView origin checks |
| `PORT` | No | HTTP port (default: 4000) |
| `WORKER_MODE` | No | `full` (default) \| `web` \| `gpu_worker` |
| `SPOTIFY_CLIENT_ID` | Yes | Spotify app client ID |
| `SPOTIFY_CLIENT_SECRET` | Yes | Spotify app client secret |
| `LALALAI_API_KEY` | No | lalal.ai cloud stem separation |
| `DEMUCS_DEVICE` | No | `cpu` (default) or `cuda` |
| `DEMUCS_MODEL_PATH` | No | Pre-downloaded Demucs model weights dir |
| `PHX_SERVER` | Yes (release) | Set to `true` to start HTTP listener |
| `POOL_SIZE` | No | Ecto pool size (default: 10) |

---

## 4. Local Development

```bash
cd /Users/jeremiah/Developer/sfa
mix deps.get
cd assets && npm install && cd ..
mix ecto.create && mix ecto.migrate
source .env && mix phx.server
# App available at http://localhost:4000
```

---

## 5. Docker Deployment

```bash
# Build
docker build -t sound-forge-alchemy:latest .

# Run (full mode)
docker run -d --name sfa -p 4000:4000 \
  -e SECRET_KEY_BASE="<generated>" \
  -e DATABASE_URL="ecto://user:pass@host/sfa_prod" \
  -e PHX_HOST="sfa.example.com" \
  -e PHX_SERVER="true" \
  -e SPOTIFY_CLIENT_ID="<id>" \
  -e SPOTIFY_CLIENT_SECRET="<secret>" \
  sound-forge-alchemy:latest

# Run migrations before starting
docker run --rm \
  -e DATABASE_URL="ecto://..." -e SECRET_KEY_BASE="<generated>" \
  sound-forge-alchemy:latest \
  eval "SoundForge.Release.migrate()"
```

---

## 6. Production Deployment (Mix Release)

```bash
# 1. Compile assets
MIX_ENV=prod mix assets.deploy

# 2. Build release
MIX_ENV=prod mix release

# 3. Run migrations
export DATABASE_URL="..." SECRET_KEY_BASE="..."
_build/prod/rel/sound_forge/bin/sound_forge eval "SoundForge.Release.migrate()"

# 4. Start
export PHX_HOST="sfa.example.com" PHX_SERVER="true"
_build/prod/rel/sound_forge/bin/sound_forge start
```

### systemd Unit

```ini
[Unit]
Description=Sound Forge Alchemy
After=network.target postgresql.service

[Service]
Type=exec
User=sfa
WorkingDirectory=/opt/sfa
EnvironmentFile=/opt/sfa/.env.production
ExecStart=/opt/sfa/bin/sound_forge start
ExecStop=/opt/sfa/bin/sound_forge stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload && systemctl enable sfa && systemctl start sfa
```

---

## 7. Health Checks

```bash
# HTTP check
curl -sf http://localhost:4000/health && echo "OK"

# Oban queue check (IEx)
Oban.check_queue(:downloads)

# DB connectivity (release)
_build/prod/rel/sound_forge/bin/sound_forge rpc \
  "SoundForge.Repo.query!(\"SELECT 1\")"
```

---

## 8. Rollback Procedure

Roll back when: `/health` returns non-200, 5xx rate spikes, or migration caused data loss.

### Docker Rollback

```bash
docker stop sfa && docker rm sfa
docker run -d --name sfa ... sound-forge-alchemy:<previous-tag>
curl -sf http://localhost:4000/health
```

### systemd Rollback

```bash
systemctl stop sfa
# Restore previous release tarball to /opt/sfa-rollback/
/opt/sfa-rollback/bin/sound_forge eval "SoundForge.Release.migrate()"
ln -sfn /opt/sfa-rollback /opt/sfa-current
systemctl start sfa
```

**Irreversible migrations**: Restore database from pre-deploy backup before rolling back binary.

---

## 9. Common Deployment Failures

### Port already in use

```bash
lsof -ti:4000 | xargs kill -9
# or use a different port:
PORT=4001 mix phx.server
```

### Database migration failure

1. Do NOT start the application with a partially migrated schema.
2. Check `schema_migrations` table for last applied version.
3. For non-idempotent failures: manually revert in `psql`, then re-run.
4. For data loss: restore from backup.

### Missing environment variables

```bash
printenv | grep -E "SECRET_KEY_BASE|DATABASE_URL|PHX_HOST|SPOTIFY|LALALAI"
```

For releases: confirm `PHX_SERVER=true` is set — without it the HTTP listener won't start.

### Assets not found (404 CSS/JS)

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite
```

### Oban workers not processing

```elixir
Application.get_env(:sound_forge, :worker_mode)  # must not be "web" for worker queues
Oban.check_queue(:downloads)                      # check if paused
Oban.resume_queue(:downloads)                     # resume if paused
```
