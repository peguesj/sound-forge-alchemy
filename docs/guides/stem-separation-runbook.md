# Stem Separation Runbook

**Application**: Sound Forge Alchemy (SFA)
**Stack**: Elixir/Phoenix, Oban, Python/Demucs, lalal.ai API
**Last Updated**: 2026-03-30

---

## 1. Overview

SFA supports two stem separation engines:

- **Local (Demucs)**: Runs `python3 -m demucs` on the server. No API costs. CPU or GPU execution.
- **Cloud (lalal.ai)**: Uploads source file to lalal.ai API, polls for completion, downloads stems. Requires `LALALAI_API_KEY`.

Jobs run as Oban workers on the `:stems` queue. Max attempts: 3.

---

## 2. Architecture

### Demucs Path

```
StemWorker.perform
  → run_demucs(track, model, job)
  → System.cmd("bash", ["-c", "python3 -m demucs --name MODEL --out OUTPUT_DIR --device DEVICE INPUT"])
  → collect_stem_files/2  (walks OUTPUT_DIR/MODEL/TRACK_NAME/*.wav)
  → Tracks.update_track   (persists stem map + stem_status: "complete")
```

Output: `priv/static/uploads/stems/{track_id}/{model}/{track_name}/*.wav`

### lalal.ai Path

```
StemWorker.perform
  → run_lalalai(track, model, job)
  → LalalAI.Client.upload/2     (POST /api/upload/)
  → LalalAI.Client.separate/4   (POST /api/separate/)
  → LalalAI.Client.poll/3       (GET /api/get-result/ every 5s, max 60 attempts = 5 min)
  → download_stems/2
  → Tracks.update_track
```

### Demucs Models

| Model | Stems | Notes |
|-------|-------|-------|
| `htdemucs` | vocals, drums, bass, other | Default |
| `htdemucs_ft` | vocals, drums, bass, other | Fine-tuned, slower |
| `htdemucs_6s` | vocals, drums, bass, guitar, piano, other | 6-stem variant |
| `mdx_extra` | vocals, drums, bass, other | MDX architecture |

---

## 3. Engine Selection

User selects engine in Settings. Stored per-user and passed as `"engine"` arg to Oban job.

| Variable | Default | Effect |
|---|---|---|
| `DEMUCS_DEVICE` | `"cpu"` | `"cpu"` or `"cuda"` — `--device` flag for Demucs |
| `DEMUCS_MODEL_PATH` | none | Pre-downloaded model weights directory |
| `LALALAI_API_KEY` | none | Required for lalal.ai engine; job fails immediately if unset |

---

## 4. Monitoring a Job

### Log Lines to Watch

```bash
tail -f /var/log/sfa/app.log | grep -E "(StemWorker|LalalAI)"
```

Key patterns:
- `[info] StemWorker starting: track=42 engine=demucs model=htdemucs`
- `[info] StemWorker demucs success: track=42`
- `[info] LalalAI separation complete: file_id=abc123`
- `[error] StemWorker failed: track=42 reason="cuda_oom"`
- `[error] StemWorker lalalai invalid API key`
- `[error] StemWorker lalalai quota exceeded`

### Oban Job Status

```elixir
import Ecto.Query
SoundForge.Repo.all(
  from j in Oban.Job,
  where: j.queue == "stems",
  order_by: [desc: j.inserted_at],
  limit: 20
) |> Enum.map(&Map.take(&1, [:id, :state, :attempt, :args, :errors]))
```

### PubSub Events

```elixir
Phoenix.PubSub.subscribe(SoundForge.PubSub, "track:42")
# Events: {:stem_started, ...}, {:stem_complete, %{stems: map}}, {:stem_failed, %{reason: reason}}
```

---

## 5. Common Failures

### Demucs Not Installed / Python Missing

```bash
python3 --version
python3 -m demucs --help
# Fix:
pip3 install demucs
```

Ensure Phoenix inherits the same PATH. If using systemd, add `Environment=PATH=...` including the Python bin directory.

### GPU Out of Memory (CUDA OOM)

**Log**: `[error] StemWorker failed: track=42 reason="cuda_oom"`

**Fix**: Fall back to CPU:
```bash
# In .env:
DEMUCS_DEVICE=cpu
```

Reduce concurrent stem jobs temporarily:
```elixir
Oban.scale_queue(queue: :stems, limit: 1)
```

### lalal.ai API Key Invalid

```bash
echo $LALALAI_API_KEY
# Test:
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: license $LALALAI_API_KEY" \
  https://www.lalal.ai/api/upload/ -F "name=test.mp3" -F "file=@/dev/null"
# Expect 200 or 400, NOT 401
```

Update key in `.env`, re-source, restart server, then retry failed jobs.

### lalal.ai Quota Exceeded

```elixir
# Pause stems queue while investigating
Oban.pause_queue(queue: :stems)
# After upgrading plan or waiting for reset:
Oban.resume_queue(queue: :stems)
```

### Output Files Not Created

```bash
ls -la /Users/jeremiah/Developer/sfa/priv/static/uploads/stems/42/
```

Expected path: `priv/static/uploads/stems/{track_id}/{model}/{track_name}/*.wav`

If empty, Demucs may have exited without error but written to a different directory. Check the `--out` argument in `stem_worker.ex:demucs_cmd/3`.

---

## 6. Recovery Procedures

```elixir
# Retry a discarded job
Oban.retry_job(job_id)

# Retry all discarded stem jobs
import Ecto.Query
SoundForge.Repo.all(from j in Oban.Job, where: j.queue == "stems" and j.state == "discarded")
|> Enum.each(&Oban.retry_job(&1.id))

# Re-enqueue with a different engine
%{"track_id" => 42, "engine" => "lalalai", "model" => "vocals"}
|> SoundForge.Workers.StemWorker.new()
|> Oban.insert()

# Clear partial output files before retrying
# (bash) rm -rf priv/static/uploads/stems/42/
# Then reset DB:
track = SoundForge.Tracks.get_track!(42)
SoundForge.Tracks.update_track(track, %{stems: %{}, stem_status: nil})
```

---

## 7. Disk Space

WAV files at 44.1 kHz stereo: ~10 MB per minute per stem.
4-minute track × 4 stems (`htdemucs`) ≈ 160 MB.

```bash
du -sh /Users/jeremiah/Developer/sfa/priv/static/uploads/stems/
# Per-track (top 20):
du -s /Users/jeremiah/Developer/sfa/priv/static/uploads/stems/* | sort -rn | head -20
# Cleanup stems older than 30 days:
find /Users/jeremiah/Developer/sfa/priv/static/uploads/stems/ \
  -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} +
```
