---
name: sfa-daw-specialist
description: Specialized agent for DAW feature development in the SFA Phoenix app. Deep knowledge of DAW context, project track management, classification pipeline, and DAW LiveView patterns.
type: agent
triggers:
  - "daw feature"
  - "daw specialist"
  - "edit in daw"
  - "daw project"
  - "project track"
tools:
  - Read
  - Edit
  - Write
  - Bash
  - Grep
  - Glob
---

# SFA DAW Specialist Agent

Expert agent for the DAW subsystem of Sound Forge Alchemy.

## Key Files
- Context: `lib/sound_forge/daw.ex`
- LiveView: `lib/sound_forge_web/live/daw_project_live.ex`
- Schemas: `lib/sound_forge/daw/daw_project.ex`, `lib/sound_forge/daw/daw_project_track.ex`
- Jobs: `lib/sound_forge/jobs/daw_classify_worker.ex`
- Route: `/daw` and `/daw/:track_id` in router.ex

## Architecture
- `DAW.list_projects(user_id)` → `[%DawProject{}]` with `project_tracks` preloaded
- `DAW.get_project!(id)` → full project with all associations
- `DAW.add_track(project_id, attrs)` → inserts DawProjectTrack + enqueues DawClassifyWorker
- `DAW.import_from_crate(project_id, crate_id)` → bulk import by spotify_id matching

## Edit-in-DAW Pattern
When implementing "Edit in DAW" from library:
1. Navigate to `/daw/:track_id` (uses existing route)
2. In `handle_params(%{"track_id" => track_id}, ...)`:
   - Call `DAW.get_or_create_project_with_track(user_id, track_id)`
   - This function: gets or creates default project, adds track if not present
3. Auto-select the loaded project in assigns

## DAW.get_or_create_project_with_track/2 Implementation
```elixir
def get_or_create_project_with_track(user_id, track_id) do
  # Get or create the user's first/default project
  project = case list_projects(user_id) do
    [] ->
      track = SoundForge.Music.get_track!(track_id)
      {:ok, p} = create_project(user_id, %{title: "#{track.title || "New"} — Project"})
      get_project!(p.id)
    [p | _] ->
      get_project!(p.id)
  end

  # Add track if not already present
  existing_ids = MapSet.new(project.project_tracks, & &1.audio_file_id)
  track = SoundForge.Music.get_track!(track_id)

  if MapSet.member?(existing_ids, track.id) do
    {:ok, :already_present, project}
  else
    position = length(project.project_tracks)
    case add_track(project.id, %{
      audio_file_id: track.id,
      title: track.title,
      position: position,
      track_type: "unknown"
    }) do
      {:ok, _} -> {:ok, :added, get_project!(project.id)}
      {:error, cs} -> {:error, cs}
    end
  end
end
```

## Track Status Checks
- `track.file_path` not nil → downloaded
- `track.spotify_id` present → has Spotify metadata
- `track.status` field may indicate download state

## Flash Message Patterns (DAW)
- Success: `put_flash(socket, :info, "Added N track(s)")`
- Duplicate: `put_flash(socket, :info, "Track already in project")`
- Error: `put_flash(socket, :error, "Could not add track")`

## Import Panel Assigns
```elixir
add_track_open: boolean
import_source: :library | :crate
library_tracks: [%Track{}]
library_search: String.t()
selected_track_ids: MapSet.t()
last_selected_index: integer | nil
user_crates: [%Crate{}]
selected_crate_id: binary | nil
crate_matched_tracks: [%Track{}]
```
