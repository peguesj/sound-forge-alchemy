# DAW Project Runbook

**Service**: Sound Forge Alchemy — DAW module
**Route**: `/daw`
**Last updated**: 2026-03-30

---

## 1. Overview

The DAW module provides a multi-track composition workspace at `/daw`. Users create named projects, import audio tracks, and arrange them with per-track volume, pan, mute, and solo controls. Each track is classified by audio type on import via an async Oban background job.

---

## 2. Architecture

```
SoundForgeWeb.DawProjectLive      (/daw)
  ├── DawContext                   (Ecto CRUD)
  ├── DawProject schema            (daw_projects table)
  ├── DawProjectTrack schema       (daw_project_tracks table)
  └── DawClassifyWorker            (Oban, queue: :daw_classify)
        └── TrackClassifier        (pure classification logic)
```

---

## 3. Creating a Project

### Via IEx

```elixir
alias SoundForge.Daw.DawContext

{:ok, project} = DawContext.create_daw_project(%{
  name: "Session 2026-03-30",
  bpm: 120, key: "A minor", time_signature: "4/4", status: "active"
})

{:ok, track} = DawContext.create_daw_project_track(%{
  name: "Kick Drums", file_path: "stems/kick.wav",
  daw_project_id: project.id
})

%{track_id: track.id}
|> SoundForge.Daw.DawClassifyWorker.new()
|> Oban.insert()
```

---

## 4. Track Classification

### How TrackClassifier Works

`TrackClassifier.classify/1` is a pure function returning `{:ok, type_string}`. Never errors — worst case returns `{:ok, "unknown"}`.

Uses vote-based classification from three signals:

1. **Name keywords**: `drums`, `bass`, `melody`, `vocals`/`vox`, `mix`/`master`, `stems`, `instrumental`, `lead`, `pad`, `fx`/`effect`/`sfx`
2. **Path keywords**: same as name, subset
3. **Analysis data**: `"has_vocals": true` → `:vocals`, `"is_percussive": true` → `:drums`, `"is_bass_heavy": true` → `:bass`

Valid `track_type` values: `drums` | `bass` | `melody` | `vocals` | `full_mix` | `stems` | `instrumental` | `lead` | `pad` | `fx` | `unknown`

### Manual Override

```elixir
track = DawContext.get_daw_project_track!(track_id)
{:ok, _} = DawContext.update_daw_project_track(track, %{track_type: "drums"})
```

### DawClassifyWorker Lifecycle

1. `add_track` event fires in LiveView
2. Track inserted with `track_type: "unknown"`
3. `DawClassifyWorker` enqueued on `:daw_classify` queue
4. Worker fetches track, runs `TrackClassifier.classify/1`, writes result
5. Oban: success → `completed`, error → retry up to 3 attempts, then `discarded`

---

## 5. Common Failures

### Classification job stuck

```elixir
import Ecto.Query
SoundForge.Repo.all(
  from j in Oban.Job,
  where: j.queue == "daw_classify" and j.state in ["executing", "retryable"]
)

# Cancel and re-enqueue
Oban.cancel_job(job_id)
%{track_id: track_id} |> SoundForge.Daw.DawClassifyWorker.new() |> Oban.insert()
```

### Track type shows "unknown"

- **Not run yet**: check Oban queue above
- **No keywords matched**: expected — rename track or apply manual override
- **Job discarded**: check `errors` field, fix underlying issue, re-enqueue

### Missing audio file on import

`file_path` is not validated for existence at the DB layer. Classification still works. Update the path:

```elixir
track = DawContext.get_daw_project_track!(track_id)
DawContext.update_daw_project_track(track, %{file_path: "correct/path/file.wav"})
```

---

## 6. Recovery Procedures

```elixir
# Re-classify a single track
%{track_id: track_id} |> SoundForge.Daw.DawClassifyWorker.new() |> Oban.insert()

# Re-classify all tracks in a project
DawContext.list_daw_project_tracks(project_id)
|> Enum.each(fn t ->
  %{track_id: t.id} |> SoundForge.Daw.DawClassifyWorker.new() |> Oban.insert()
end)

# Re-classify all unknown tracks system-wide
import Ecto.Query
SoundForge.Daw.DawProjectTrack
|> where([t], t.track_type == "unknown")
|> SoundForge.Repo.all()
|> Enum.each(fn t ->
  %{track_id: t.id} |> SoundForge.Daw.DawClassifyWorker.new() |> Oban.insert()
end)
```

---

## 7. Data Model

### daw_projects

| Column | Type | Notes |
|---|---|---|
| `id` | integer | PK |
| `name` | string | Required, 1–255 chars |
| `bpm` | integer | Optional |
| `key` | string | Optional (e.g. "C minor") |
| `time_signature` | string | Optional (e.g. "4/4") |
| `status` | string | `active` (default) \| `draft` \| `archived` |

### daw_project_tracks

| Column | Type | Notes |
|---|---|---|
| `id` | integer | PK |
| `daw_project_id` | integer | FK |
| `name` | string | Required |
| `file_path` | string | Not validated for existence |
| `track_type` | string | Enum — see Section 4 |
| `volume` | float | 0.0–2.0, default 1.0 |
| `pan` | float | -1.0–1.0, default 0.0 |
| `muted` | boolean | default false |
| `soloed` | boolean | default false |
| `position` | integer | Track order, default 0 |
| `analysis_data` | map (jsonb) | Optional; feeds classifier |

### Useful Queries

```sql
-- Projects with track counts
SELECT dp.id, dp.name, COUNT(dpt.id) AS tracks
FROM daw_projects dp
LEFT JOIN daw_project_tracks dpt ON dpt.daw_project_id = dp.id
GROUP BY dp.id ORDER BY dp.inserted_at DESC;

-- Unclassified tracks
SELECT id, name, file_path FROM daw_project_tracks
WHERE track_type = 'unknown' ORDER BY inserted_at DESC;
```

---

## 8. Export

No HTTP export endpoint exists yet. Ad-hoc export via IEx:

```elixir
project = DawContext.get_daw_project!(project_id)
tracks = DawContext.list_daw_project_tracks(project.id)

data = %{
  project: Map.take(project, [:name, :bpm, :key, :time_signature]),
  tracks: Enum.map(tracks, &Map.take(&1, [:name, :file_path, :track_type, :volume, :pan, :position]))
}
File.write!("/tmp/project_#{project.id}.json", Jason.encode!(data, pretty: true))
```
