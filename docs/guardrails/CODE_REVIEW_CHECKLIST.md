# Code Review Checklist -- Sound Forge Alchemy

Use this checklist for every code review. Items are grouped by category and ordered by severity within each category. A single failure in the **Critical** section blocks merge.

---

## Critical (Merge Blockers)

### Security
- [ ] No hardcoded credentials (Spotify client_id/secret, API keys, database passwords)
- [ ] All user-provided file paths sanitized through `Path.basename/1` and sandboxed to `SoundForge.Storage.base_path/0`
- [ ] No `String.to_atom/1` on user input (atom table exhaustion)
- [ ] No raw SQL interpolation -- all queries use parameterized Ecto queries with `^variable`
- [ ] No secrets committed in config files (check `config/config.exs`, `config/dev.exs`)

### Data Integrity
- [ ] All new schemas use `@primary_key {:id, :binary_id, autogenerate: true}`
- [ ] All new schemas use `@foreign_key_type :binary_id`
- [ ] All new schemas use `timestamps(type: :utc_datetime)`
- [ ] Multi-step database operations use `Ecto.Multi`
- [ ] Job status transitions are validated (no backward transitions)
- [ ] Foreign key constraints present on all `belongs_to` associations
- [ ] No audio binary data stored in the database

### Concurrency & Process Safety
- [ ] No GenServers holding domain entity state (DB is source of truth)
- [ ] No Python Port calls in the LiveView/controller request path
- [ ] No synchronous Port calls exceeding 5 seconds without Oban wrapper
- [ ] All external HTTP calls go through Oban workers
- [ ] Port crash handlers present (`handle_info` for non-zero `exit_status`)

---

## Required (Must Fix Before Merge)

### Oban Workers
- [ ] Worker uses correct queue from config (`download`, `processing`, `analysis`)
- [ ] Worker has `max_attempts` set (default 3)
- [ ] Worker broadcasts progress via PubSub after every status change
- [ ] Worker cleans up files on failure
- [ ] Worker logs failures with context (job_id, track_id, attempt, error)
- [ ] Worker uses integer 0-100 for progress (not floats)
- [ ] Worker handles all expected error cases (network failure, Port crash, file not found)

### LiveView
- [ ] Collections use `stream/3`, not raw list assigns
- [ ] Parent element has `phx-update="stream"` with a DOM id
- [ ] Each stream child uses the stream-provided DOM id
- [ ] PubSub subscriptions created in `mount/3` only when `connected?(socket)`
- [ ] Forms use `to_form/2` and `@form` assign, not raw changesets
- [ ] All key elements have unique DOM ids for testing
- [ ] Template wraps content in `<Layouts.app flash={@flash}>`
- [ ] No `<.flash_group>` calls outside of `layouts.ex`
- [ ] Icons use `<.icon name="hero-...">` component
- [ ] No deprecated `live_redirect`/`live_patch` -- use `<.link navigate={}>` / `<.link patch={}>`

### Ecto & Database
- [ ] Associations preloaded in queries when accessed in templates
- [ ] Search queries use `ilike` for case-insensitive matching
- [ ] `validate_number/3` does not use `:allow_nil` (unsupported)
- [ ] Changeset fields accessed via `Ecto.Changeset.get_field/2`, not map access
- [ ] Programmatic fields (e.g., `user_id`, `track_id`) set explicitly, not in `cast/3`
- [ ] Migration generated with `mix ecto.gen.migration` (correct timestamp)
- [ ] Migration is reversible (has `down` or uses `alter`/`drop` that can be reversed)

### HTTP & External Services
- [ ] HTTP requests use `Req` (not HTTPoison, Tesla, :httpc)
- [ ] Spotify token cache uses ETS, not GenServer state or database
- [ ] Spotify URLs validated through `SoundForge.Spotify.URLParser` before processing
- [ ] Error responses from external APIs handled (non-200 status codes, network errors)

---

## Recommended (Should Fix, Non-Blocking)

### Code Quality
- [ ] New public functions have `@doc` strings
- [ ] New modules have `@moduledoc` strings
- [ ] No compiler warnings (`mix compile --warnings-as-errors`)
- [ ] Code formatted (`mix format`)
- [ ] No unused imports or aliases
- [ ] No nested module definitions in the same file
- [ ] Pattern matching preferred over conditional branching where appropriate
- [ ] Pipe chains start with a data value, not a function call

### Testing
- [ ] Tests exist for happy path
- [ ] Tests exist for error cases
- [ ] Tests exist for edge cases (empty input, nil values, boundary values)
- [ ] All processes started with `start_supervised!/1`
- [ ] External services mocked with Mox
- [ ] No `Process.sleep/1` in tests (use `Process.monitor/1` + `assert_receive`)
- [ ] No assertions against raw HTML (use `has_element?/2`, `element/2`)
- [ ] Tests reference elements by DOM id, not text content
- [ ] LiveView tests use `LazyHTML` selectors for debugging
- [ ] `mix test` passes with `--warnings-as-errors`

### Performance
- [ ] No N+1 queries (check `Repo.all` inside `Enum.map`)
- [ ] Large collections use streams, not full list loads
- [ ] File operations use streaming for files over 10 MB
- [ ] Port calls have appropriate timeouts set
- [ ] Oban queue concurrency limits are appropriate for the workload
- [ ] No unbounded list growth in LiveView assigns

### Phoenix 1.8 Compliance
- [ ] Tailwind CSS v4 import syntax used in `app.css` (`@import "tailwindcss" source(none)`)
- [ ] No `@apply` in raw CSS
- [ ] No inline `<script>` tags (use colocated JS hooks with `:type={Phoenix.LiveView.ColocatedHook}`)
- [ ] Colocated hook names start with `.` prefix
- [ ] No external vendor script `src` or link `href` in layouts
- [ ] Class attributes use list syntax for conditional classes
- [ ] HEEx comments use `<%!-- comment --%>` syntax
- [ ] Interpolation uses `{...}` in attributes and tag bodies, `<%= %>` for block constructs only

---

## Audio Processing Specific

### File Management
- [ ] Audio files stored via `SoundForge.Storage`, not direct filesystem calls
- [ ] File paths use `Path.join/2` (not string concatenation)
- [ ] Temporary files cleaned up after processing
- [ ] File existence checked before operations (no assumed paths)
- [ ] Storage directories created with `File.mkdir_p!/1` before writes

### Port Protocol
- [ ] Python script path resolved via `:code.priv_dir(:sound_forge)`
- [ ] Port opened with `{:spawn_executable, python_path}` (not `:spawn`)
- [ ] Port uses `:binary` and `:exit_status` options
- [ ] JSON protocol used for Port communication (not raw text)
- [ ] Feature list validated against `@valid_features` before Port call
- [ ] Buffer accumulates until exit_status message (no partial parse)

### Job Pipeline
- [ ] Download -> Processing -> Analysis pipeline respects dependencies
- [ ] A processing job cannot start without a completed download
- [ ] An analysis job cannot start without a completed download
- [ ] Job chaining uses Oban's `insert/2` after completion, not hardcoded sequences
- [ ] Each pipeline stage is independently retryable

---

## Review Process

1. **Author** runs `mix precommit` before requesting review
2. **Reviewer** checks all Critical items first; any failure blocks merge
3. **Reviewer** checks Required items; all must pass for merge
4. **Reviewer** notes Recommended items as follow-up tasks
5. **Reviewer** checks Audio Processing items for any audio-related changes
6. **Author** addresses all Critical and Required items
7. **Merge** after all Critical and Required items pass
